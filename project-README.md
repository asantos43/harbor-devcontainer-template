# {{PROJECT_NAME}}

> _One line on what this project's Harbor tasks are for._

A [Harbor](https://github.com/harbor-framework/harbor) eval-task project, using the
standard Harbor dev container. Open in VS Code and **Reopen in Container**; the
workspace is at `/workspace`.

## Layout

Harbor tasks live in `task/`, one directory per task. Run output goes to `jobs/` at
the project root.

```
task/<task-name>/
├── instruction.md          # what the agent is asked to do
├── task.toml               # metadata, timeouts, resource requests
├── environment/Dockerfile  # the container the agent works in
├── solution/solve.sh       # reference solution (run by the `oracle` agent)
└── tests/                  # pytest assertions -> /logs/verifier/reward.txt
```

## Daily commands

```bash
harbor init -t <name> -o task                            # scaffold task/<name>
harbor task start-env -p task/<name> -e docker -a -i     # interactive task container
harbor run  -p task/<name> -a oracle                     # reference run; expect reward 1.0
harbor view ./jobs                                       # browse trajectories
```

Run output goes to `jobs/` (gitignored).

Check the container itself is wired up correctly (after any rebuild):

```bash
.devcontainer/verify-setup.sh      # runs a throwaway oracle trial; expects PASS
```

To stop the container, from the **host** (not inside it):

```bash
./stop-devcontainer.sh             # add --remove to delete it as well
```

> ⚠️ Always call plain `harbor`. It is a shim at `/usr/local/bin/harbor` that
> translates `/workspace` paths to the host paths the Docker daemon needs. Calling
> `~/.local/bin/harbor` or `uvx harbor` directly bypasses it and every trial silently
> scores 0.

## Container, updates, troubleshooting

See the template's README: `~/dev/templates/harbor-devcontainer/README.md`.
To bump the pinned toolchain, run `.devcontainer/update-toolchain.sh` **on the host**.
