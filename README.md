# Harbor devcontainer template

A standard, versioned dev container for authoring and running
[Harbor](https://github.com/harbor-framework/harbor) eval tasks — the framework
behind Terminal-Bench 2.0. One template, reused by every Harbor project, with a
one-command path to newer Harbor and tool versions.

Preinstalled in the container:

| Tool | Source |
| --- | --- |
| `harbor` CLI | Dockerfile; pinned in `versions.env`, installed with `uv tool install` |
| Python, as `python` and `python3` | Dockerfile; `uv python install --default`, pinned in `versions.env` |
| `uv` / `uvx` | Dockerfile; pinned in `versions.env` |
| zsh | Dockerfile (oh-my-zsh, plugins and atuin come from the `common-utils` feature and `post-create.sh`) |
| Docker CLI + Compose v2 | `docker-outside-of-docker` feature, talking to the **host** daemon |
| `gh` | `github-cli` feature |

The `--default` flag on `uv python install` matters: without it uv installs only a
versioned `python3.13` and plain `python` / `python3` are absent, which breaks
anything that shells out to `python3`.

The workspace is mounted at **`/workspace`**, and Harbor tasks live in **`task/`**:

```
<project>/
├── .devcontainer/
├── task/                  # one directory per Harbor task  <- your work goes here
├── jobs/                  # run output (gitignored, created on first run)
├── stop-devcontainer.sh   # stop the container (run on the host)
└── README.md
```

---

## 1. Prerequisites on the host

- **Docker running**, and your user in the `docker` group
  (`docker version` must work without `sudo`).
- **VS Code with the Dev Containers extension**, or the
  [`devcontainer` CLI](https://github.com/devcontainers/cli)
  (`npm install -g @devcontainers/cli`).
- `curl` and `jq`, if you want to run `update-toolchain.sh`.

API keys are **not** taken from your host shell. Put them in
`.devcontainer/devcontainer.env` (see [Configuration](#7-configuration-reference)).

---

## 2. Start a new project

From the root of this template repo:

```bash
./bin/new-harbor-project.sh my-task-project   # prints the path it created
code <project-dir>                            # then: Reopen in Container
```

Then **Reopen in Container** in VS Code. Or, without VS Code:

```bash
devcontainer up   --workspace-folder <project-dir>
devcontainer exec --workspace-folder <project-dir> zsh
```

`new-harbor-project.sh` copies `.devcontainer/`, `task/` and `stop-devcontainer.sh`,
drops a `.gitignore`
(which ignores `jobs/` and the secrets file), writes a project `README.md`, and runs
`git init`. The second argument overrides the parent directory.

On first start, `post-create.sh` prints a status block — the harbor version, the host
Docker server version, and whether the mirror mount works. **If it warns that the
mirror mount is broken, stop and fix that first**; see
[Troubleshooting](#8-troubleshooting).

To prove the container can actually run a trial, run the self-check from `/workspace`
**inside** the container:

```bash
.devcontainer/verify-setup.sh
```

It scaffolds a throwaway task with a real assertion, runs it with the `oracle` agent,
checks the reward came back as 1.0, and cleans up after itself. Run it after every
rebuild or template sync — it exercises the exact path that breaks when the mirror
mount or the shim is not working.

---

## 3. Harbor quickstart, inside the container

Work from `/workspace`.

```bash
harbor init -t ssh-key-pair -o task
```

`-o task` puts it in the project's task directory, which is where every task belongs.
It produces:

```
task/ssh-key-pair/
├── instruction.md          # what the agent is asked to do, in natural language
├── task.toml               # metadata: author, difficulty, tags, timeouts, resources
├── environment/Dockerfile  # the container the agent works in
├── solution/solve.sh       # reference solution, used by the `oracle` agent
└── tests/
    ├── test_outputs.py     # pytest assertions that decide the reward
    └── test.sh             # entrypoint that runs the tests
```

Poke at the environment by hand before writing the solution:

```bash
harbor task start-env -p task/ssh-key-pair -e docker -a -i
```

Run the reference solution end to end. The `oracle` agent just executes
`solution/solve.sh`, so **this must report reward 1.0** — if it does not, either the
task is wrong or the container wiring is (see
[How the Docker wiring works](#5-how-the-docker-wiring-works-and-why)):

```bash
harbor run -p task/ssh-key-pair -a oracle
```

Then try a real agent, and browse the trajectories:

```bash
harbor run -p task/ssh-key-pair -a terminus-2 -m anthropic/claude-haiku-4-5
harbor view ./jobs
```

Results land in `./jobs` at the project root, not under `task/` (override with
`-o/--jobs-dir`). Inside each trial, the
reward comes from **`/logs/verifier/reward.txt`**, written by the verifier inside the
task container and collected through a bind mount — which is why the path handling
below matters.

Useful extras: `harbor check` (task quality against a rubric), `harbor analyze`
(trajectory analysis), `harbor run -d terminal-bench@2.0 -a oracle -n 4` (run a
published dataset), `harbor agent list` / `harbor dataset list`.

---

## 4. Everyday commands

| Command | What it does |
| --- | --- |
| `harbor init -t <name> -o task` | scaffold a new task into `task/<name>` |
| `harbor task start-env -p task/<name> -e docker -a -i` | interactive shell in the task container |
| `harbor run -p task/<name> -a oracle` | run the reference solution; expect reward 1.0 |
| `harbor run -p task/<name> -a <agent> -m <model>` | run a real agent |
| `harbor view ./jobs` | web UI over past trials |
| `cdw` | `cd` to the mirror of `/workspace` at its host path |
| `harbor-jobs` | list the most recent job directories |
| `.devcontainer/verify-setup.sh` | end-to-end self-check; expects `PASS` |
| `./stop-devcontainer.sh` | **on the host:** stop this project's container |
| `./stop-devcontainer.sh --remove` | **on the host:** stop and delete it, so the next start re-runs `postCreateCommand` |

---

### Stopping the container

From the host, in the project directory:

```bash
./stop-devcontainer.sh              # stop
./stop-devcontainer.sh --remove     # stop and delete
```

It finds the container by the `devcontainer.local_folder` label the CLI stamps on it,
so it keeps working if you rename the container. `--remove` deletes the container but
never the workspace — that is a bind mount of your project directory — so the next
start recreates it from the image and re-runs `postCreateCommand`. Running it *inside*
the container is refused, with the host path to run instead.

## 5. How the Docker wiring works, and why

**Task containers are siblings, not children.** The `docker-outside-of-docker` feature
bind-mounts the host's `/var/run/docker.sock` into this container. Every container
Harbor creates is therefore created by the **host** daemon and sits next to this one.
That is deliberate: the host image cache is reused, builds are fast, and task
containers are not constrained by a nested daemon.

It also creates one sharp edge.

**The host daemon resolves bind-mount paths against the host filesystem.** Harbor
bind-mounts its jobs directory into every task container to collect `/logs` — agent
logs, artifacts, and the verifier's `reward.txt`. If Harbor ran with `cwd=/workspace`,
it would hand `/workspace/jobs/...` to the host daemon. The host has no `/workspace`,
so the daemon would silently create an empty root-owned directory there, the reward
file would land where Harbor cannot read it, and **every trial would score 0** — with
no error message.

Two things prevent that:

1. **A mirror mount.** `devcontainer.json` mounts the project twice: at `/workspace`,
   and again at `${localWorkspaceFolder}` — the *same absolute path the host knows it
   by*, exposed as `$HOST_WORKSPACE`. Both paths are the same physical directory, so
   a file written through one is visible through the other; only the second is
   meaningful to the host daemon.
2. **A shim at `/usr/local/bin/harbor`.** It rewrites `$PWD` and any `/workspace/...`
   argument to the `$HOST_WORKSPACE` equivalent, then `exec`s the real binary at
   `~/.local/bin/harbor`. This is why `/usr/local/bin` must come first on `PATH`.

You edit in `/workspace` and the shim is invisible.

> ⚠️ **Invoking `~/.local/bin/harbor` or `uvx harbor` directly bypasses the shim** and
> will produce silently-zero rewards. Always call plain `harbor`.

---

## 6. Updating

Run on the **host**, from the project directory:

```bash
.devcontainer/update-toolchain.sh            # or --dry-run to just look
```

It queries PyPI and GitHub for the latest `harbor` and `uv`, rewrites
`.devcontainer/versions.env`, runs `devcontainer outdated` and `devcontainer upgrade`
to refresh the feature digests in `devcontainer-lock.json`, and prints the diff.
Then rebuild and re-verify before committing:

```bash
devcontainer build --workspace-folder .      # or VS Code: Rebuild Container
.devcontainer/verify-setup.sh                # inside the container; must print PASS
```

`versions.env` is the **only** place to hand-edit a pin — it is `COPY`'d by the
Dockerfile, so changing it invalidates the build cache and the rebuild reinstalls
automatically. `PYTHON_VERSION` is not bumped automatically; the script prints
Harbor's `requires_python` floor so you can decide.

To pull a newer template into an **existing** project:

```bash
./bin/sync-template.sh <project-dir>   # from the root of this template repo
```

It shows a diff first, never overwrites `devcontainer.env`, and never touches tasks
already in `task/` (it only creates that directory if the project predates the
convention). The workflow is: bump and commit in the template repo, then
`sync-template.sh` into each project, then rebuild and run
`.devcontainer/verify-setup.sh`.

---

## 7. Configuration reference

| Knob | Where | Notes |
| --- | --- | --- |
| `HARBOR_VERSION` | `.devcontainer/versions.env` | exact Harbor release to install |
| `PYTHON_VERSION` | `.devcontainer/versions.env` | interpreter uv installs; must satisfy Harbor's `>=3.12` |
| `UV_VERSION` | `.devcontainer/versions.env` | uv installer version |
| `INSTALL_AGENT_CLIS` | `.devcontainer/versions.env` | `1` installs the Claude Code and OpenCode CLIs, needed for `harbor run -a claude-code` |
| Feature versions | `devcontainer.json` + `devcontainer-lock.json` | managed by `devcontainer upgrade` |
| Secrets (`ANTHROPIC_API_KEY`, …) | `.devcontainer/devcontainer.env` | gitignored; created by `initialize.sh`; passed with `--env-file`; `KEY=value` per line, no quotes, no `export` |
| `TZ` | `devcontainer.json` → `containerEnv` | defaults to `America/Sao_Paulo` |
| `HOST_WORKSPACE` | `devcontainer.json` → `containerEnv` | set automatically; the shim depends on it |
| `harbor-cache` volume | `devcontainer.json` → `mounts` | downloaded datasets/tasks, shared across every project from this template |
| Container name | `devcontainer.json` → `runArgs` | derived from the folder name |

---

## 8. Troubleshooting

**Every trial scores 0, or `jobs/.../verifier/reward.txt` is missing or empty.**
The path translation is not happening. Check `echo $HOST_WORKSPACE` is set and that
the directory exists, and confirm you are calling plain `harbor`
(`command -v harbor` must print `/usr/local/bin/harbor`, not `/root/.local/bin/harbor`).
On the **host**, look for a stray root-owned `/workspace` directory — its existence is
the fingerprint of this failure. Re-running `post-create.sh` reprints the mirror-mount
check.

**`docker: permission denied` or `Cannot connect to the Docker daemon`.**
`docker version --format '{{.Server.Version}}'` should print the *host's* version.
If not, the socket is not reaching the container: confirm the host daemon is up and
that your host user is in the `docker` group, then rebuild.

**A bind mount comes up empty or permission-denied on Fedora.**
SELinux. The `docker-outside-of-docker` feature sets `securityOpt: label=disable`,
which normally covers it; if a mount still misbehaves, append `,z` to that mount's
string in `devcontainer.json`.

**Disk filling up.**
Harbor's task images and containers land in **host** Docker, not an isolated daemon.
Inspect with `docker system df`, list leftovers with
`docker ps -a --filter status=exited`, and prune deliberately. Do not run a blanket
`docker system prune -a` unless you are willing to lose unrelated host images.

**Files created in the container are root-owned on the host.**
Expected: the container runs as `root` (`remoteUser`), and the workspace is a bind
mount, so anything Harbor or you create inside it belongs to `root` outside it. Edit
those files from inside the container. To hand a directory back to your host user:
`sudo chown -R "$USER:$USER" <path>` on the host.

**`harbor: command not found` after a rebuild.**
`PATH` ordering. `/usr/local/bin` must precede `/root/.local/bin`; both the Dockerfile
`ENV PATH` and `.zshrc` set this.

**`docker: Error response from daemon: Conflict. The container name ... is already in use`.**
The container name comes from the folder name (`runArgs → --name`). Two checkouts with
the same folder name collide; rename one, or remove the stale container.

**The `harbor view` UI does not open.**
It binds `127.0.0.1` and takes the first free port in `8080-8089`. Port 8080 is
forwarded explicitly; if it was taken and the viewer picked another, accept the
auto-forward notification or check the Ports panel.

---

## 9. Links

- Harbor docs — <https://www.harborframework.com/docs>
- Task tutorial — <https://www.harborframework.com/docs/tasks/task-tutorial>
- Task structure — <https://www.harborframework.com/docs/tasks>
- Running Terminal-Bench — <https://www.harborframework.com/docs/tutorials/running-terminal-bench>
- Source — <https://github.com/harbor-framework/harbor>
- Dev Containers spec — <https://containers.dev>

---

## 10. License

MIT — see [LICENSE](LICENSE).
