# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workflow: branch first, PR at the end

**Every change starts on a new branch.** Create it before making any edit — never commit
directly to `master`, however small the change:

```bash
git checkout -b <short-descriptive-name>
```

**Finish, test and validate the change on that branch** (see [Verifying a change](#verifying-a-change)),
and only then propose it as a pull request:

```bash
git push -u origin <short-descriptive-name>
gh pr create --fill        # gh is installed on the host and in the container
```

**Once the PR is merged, delete the branch** and return to `master`:

```bash
git checkout master && git pull --ff-only
git branch -d <short-descriptive-name>
git push origin --delete <short-descriptive-name>
```

This is not only convention: a repository ruleset protects `master` against direct
pushes, force-pushes and deletion, and requires a pull request, so the branch is the
only way in. The ruleset targets the default branch only, which is what leaves merged
feature branches deletable.

The PR comes after verification, not before. That order matters here more than in an
ordinary repo: `.devcontainer/` is copied verbatim into downstream projects, where a
broken `post-create.sh` or shim produces silently-zero rewards rather than an error, so
an unverified change is not obviously wrong until it costs someone an eval run.

## What this repository is

A **template**, not an application and not a Harbor project. It contains no build, no
package manifest and no test suite — only shell scripts, a Dockerfile and dev container
config that get *copied into* other projects by [bin/new-harbor-project.sh](bin/new-harbor-project.sh)
(new project) and [bin/sync-template.sh](bin/sync-template.sh) (re-apply to an existing one).

Consequences for any change here:

- Almost nothing in this checkout runs on the host. `.devcontainer/*.sh` (except
  `initialize.sh` and `update-toolchain.sh`) executes **inside** a container, as `root`,
  with the project at `/workspace`.
- Edits ship to downstream projects only when someone runs `sync-template.sh` and
  rebuilds. Commit here first; sync second.
- If you add a root-level file that should travel with the template, both `bin/` scripts
  need updating — `sync-template.sh` copies `.devcontainer/*` wholesale but names
  `stop-devcontainer.sh` and `task/` explicitly.

## The invariant that matters most

Task containers Harbor creates are **siblings** of the dev container (the docker socket
is bind-mounted from the host), so the host daemon resolves every bind-mount path against
the *host* filesystem, where `/workspace` does not exist. If Harbor is handed a
`/workspace/...` path, `reward.txt` lands somewhere it cannot be read back and **every
trial silently scores 0** — no error, just zeros.

Three files hold that together and must stay consistent:

- [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) — mounts the project
  *twice*, at `/workspace` and again at its host path, exposed as `$HOST_WORKSPACE`.
- [.devcontainer/harbor-shim.sh](.devcontainer/harbor-shim.sh) — installed as
  `/usr/local/bin/harbor`; rewrites `$PWD` and `/workspace/...` arguments to their
  `$HOST_WORKSPACE` equivalents, then `exec`s the real binary in `~/.local/bin`.
- PATH ordering — `/usr/local/bin` must precede `/root/.local/bin` in *both* the
  Dockerfile `ENV PATH` and [.devcontainer/.zshrc](.devcontainer/.zshrc), so the shim
  wins over the real binary.

Never invoke `~/.local/bin/harbor` or `uvx harbor` in scripts or docs; always plain
`harbor`.

## Verifying a change

There is no unit test suite. The real check is an end-to-end oracle trial:

```bash
bash -n .devcontainer/post-create.sh          # syntax, on the host
.devcontainer/verify-setup.sh                 # INSIDE the container, from /workspace
```

`verify-setup.sh` scaffolds a throwaway task, runs it with the `oracle` agent and
requires reward 1.0. Run it after any change to the container wiring, and after any
`sync-template.sh`. A reward of 0 or a missing `reward.txt` means the mirror mount or the
shim is broken, not that the task is wrong.

`post-create.sh` runs **only at container creation**, so testing an edit to it normally
means `./stop-devcontainer.sh --remove` (on the host) plus a rebuild. Faster loop: run it
directly in a throwaway container off an already-built image from this template,
reproducing the two mounts and the socket:

```bash
docker run -d --name pc-test \
  -v "$PWD":/workspace -v "$PWD":"$PWD" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e HOST_WORKSPACE="$PWD" -w /workspace <vsc-...-image> sleep 1200
docker exec pc-test bash .devcontainer/post-create.sh   # must exit 0
docker exec pc-test bash .devcontainer/post-create.sh   # re-run: must be a no-op
```

Use a scratch copy of the project rather than the repo itself — the container runs as
root and leaves root-owned files behind.

## Conventions in the container scripts

- **`post-create.sh` may never abort container creation.** It runs under
  `set -euo pipefail`, so every optional step is guarded (`... || echo "warning: ..." >&2`)
  and every install is skipped when its target already exists. An unguarded failure kills
  the readiness summary and the sanity checks with it.
- **`~/.zshrc` is owned by the template.** `post-create.sh` copies
  `.devcontainer/.zshrc` over it, so third-party installers must be stopped from
  appending to it (`PROFILE=/dev/null` for nvm, an unrecognised `SHELL` for bun);
  `.zshrc` then loads the tool explicitly, as it does for atuin, nvm and bun.
- **Non-interactive shells read no rc file.** Anything task tests, agents or VS Code
  tasks must be able to call has to be on the system PATH — via the Dockerfile `ENV PATH`
  or a symlink into `/usr/local/bin` (that is why `uv python install` uses `--default`,
  and why `node`/`npm`/`npx`/`bun` are linked there).
- **`versions.env` is the only place to hand-edit an image pin**, and the Dockerfile
  sources it rather than hardcoding versions. It is `COPY`'d early, so editing it
  invalidates the build cache and forces a full reinstall — pins for things installed by
  `post-create.sh` (e.g. the nvm tag) deliberately stay inline there, where a bump costs
  no rebuild. `update-toolchain.sh` (host-only) rewrites `HARBOR_VERSION` and
  `UV_VERSION`; `PYTHON_VERSION` is by hand.
- Comments in these files explain *why*, often at length, because the failure modes are
  silent. Match that when editing.

## Host vs container

| On the host | Inside the container |
| --- | --- |
| `bin/new-harbor-project.sh <name> <parent-dir>` | `harbor init -t <name> -o task` |
| `bin/sync-template.sh <project-dir> [--yes]` | `harbor run -p task/<name> -a oracle` |
| `.devcontainer/update-toolchain.sh [--dry-run]` | `.devcontainer/verify-setup.sh` |
| `./stop-devcontainer.sh [--remove]` | `harbor view ./jobs` |

`stop-devcontainer.sh` refuses to run inside the container; `update-toolchain.sh` needs
the `devcontainer` CLI, which lives on the host.

## Documentation

Three READMEs, with different audiences — a change usually belongs in more than one:
[README.md](README.md) documents the template itself, [project-README.md](project-README.md)
is the templated README written into each generated project (`{{PROJECT_NAME}}` is
substituted), and [task/README.md](task/README.md) travels into projects as the task
directory convention.

Use relative paths in all documentation — never absolute or `~`-prefixed paths from a
particular machine.
