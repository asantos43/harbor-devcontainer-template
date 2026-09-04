#!/usr/bin/env bash
# Runs inside the container once, after creation. Sets up the interactive shell and
# sanity-checks the wiring that Harbor depends on.
#
# Nothing here may abort container creation, so every optional step is guarded.
set -euo pipefail

# The project is mounted twice (at /workspace and at $HOST_WORKSPACE), so git sees the
# same repo under two paths and would otherwise refuse both as "dubious ownership".
git config --global --add safe.directory '*'

# ---------------------------------------------------------------------------
# Shell: oh-my-zsh comes from the common-utils feature (so it is version-locked);
# only the plugins and atuin are installed here.
# ---------------------------------------------------------------------------
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

clone_plugin() {
    local url="$1" dest="$2"
    [ -d "$dest" ] && return 0
    git clone --depth 1 -- "$url" "$dest" >/dev/null 2>&1 \
        || echo "warning: could not clone $url" >&2
}

clone_plugin https://github.com/zsh-users/zsh-autosuggestions.git \
             "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_plugin https://github.com/zsh-users/zsh-syntax-highlighting.git \
             "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
clone_plugin https://github.com/zdharma-continuum/fast-syntax-highlighting.git \
             "$ZSH_CUSTOM/plugins/fast-syntax-highlighting"

if [ ! -x "$HOME/.atuin/bin/atuin" ]; then
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh \
        | sh -s -- --non-interactive >/dev/null 2>&1 \
        || echo "warning: atuin install failed" >&2
fi

cp .devcontainer/.zshrc  "$HOME/.zshrc"
cp .devcontainer/.zshenv "$HOME/.zshenv"

# ---------------------------------------------------------------------------
# JavaScript toolchain: nvm (plus the Node LTS) and bun, both under $HOME.
#
# Left to themselves both installers append their own PATH lines to the ~/.zshrc
# just copied in above, which the template owns; PROFILE=/dev/null and a shell name
# bun does not recognise suppress that, and .zshrc loads both explicitly instead.
# ---------------------------------------------------------------------------
nvm_version=0.40.3   # not in versions.env: that file is COPYed by the Dockerfile,
                     # so bumping it here costs no image rebuild. Bump by hand.
export NVM_DIR="$HOME/.nvm"

if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${nvm_version}/install.sh" \
        | PROFILE=/dev/null bash >/dev/null 2>&1 \
        || echo "warning: nvm install failed" >&2
fi

node_version='NOT FOUND'

if [ -s "$NVM_DIR/nvm.sh" ]; then
    # nvm.sh is not written for `set -eu`: it reads unset variables and returns
    # non-zero from harmless paths, so relax both around it.
    set +eu
    . "$NVM_DIR/nvm.sh"
    nvm install --lts >/dev/null 2>&1 && nvm alias default 'lts/*' >/dev/null 2>&1 \
        || echo "warning: node install failed" >&2
    node_default_bin="$NVM_DIR/versions/node/$(nvm version default)/bin"
    set -eu
    node_version="$(node --version 2>/dev/null || echo 'NOT FOUND')"
fi

if [ ! -x "$HOME/.bun/bin/bun" ]; then
    curl -fsSL https://bun.sh/install | SHELL=/bin/sh bash >/dev/null 2>&1 \
        || echo "warning: bun install failed" >&2
fi

bun_version="$("$HOME/.bun/bin/bun" --version 2>/dev/null || echo 'NOT FOUND')"

# Task tests, agents and VS Code tasks shell out non-interactively, where no rc file
# is read at all - the same reason the Dockerfile insists on a default `python3`. Link
# the default toolchain onto the system PATH so those see it too. An interactive
# `nvm use` still wins: nvm.sh prepends its own bin directory.
for bin in "${node_default_bin:-}"/node "${node_default_bin:-}"/npm \
           "${node_default_bin:-}"/npx "$HOME/.bun/bin/bun"; do
    [ -x "$bin" ] || continue   # `&&` here would abort the script on the last miss
    ln -sf "$bin" "/usr/local/bin/$(basename "$bin")"
done

# ---------------------------------------------------------------------------
# Sanity checks: surface a broken socket mount or a broken mirror mount NOW, at
# create time, instead of as mysteriously-zero rewards during the first eval.
# ---------------------------------------------------------------------------
harbor_version="$(/root/.local/bin/harbor --version 2>/dev/null || echo 'NOT FOUND')"

docker_server='UNREACHABLE'
if docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
    docker_server="$(docker version --format '{{.Server.Version}}')"
fi

mirror='BROKEN'
if [ -n "${HOST_WORKSPACE:-}" ] && [ -d "$HOST_WORKSPACE" ]; then
    probe="$(mktemp -p /workspace .mirror-probe-XXXXXX)"
    [ -f "${HOST_WORKSPACE}/$(basename "$probe")" ] && mirror='ok'
    rm -f "$probe"
fi

echo ""
echo "Harbor dev container ready."
echo ""
echo "  harbor           : ${harbor_version}"
echo "  node             : ${node_version}  (nvm ${nvm_version})"
echo "  bun              : ${bun_version}"
echo "  docker daemon    : ${docker_server}  (host daemon, sibling containers)"
echo "  HOST_WORKSPACE   : ${HOST_WORKSPACE:-<unset>}"
echo "  mirror mount     : ${mirror}"
echo ""
if [ "$mirror" != "ok" ]; then
    echo "  WARNING: the mirror mount is not working. Harbor trials will score 0."
    echo "           See the Troubleshooting section of the template README."
    echo ""
fi
echo "  Quickstart:  harbor init my-task"
echo "               harbor run -p my-task -a oracle     # must report reward 1.0"
echo "               harbor view ./jobs"
echo ""
