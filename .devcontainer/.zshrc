# Zsh configuration for the Harbor devcontainer.
# Copied to $HOME by post-create.sh, overwriting the stock one oh-my-zsh installs.

export ZSH="$HOME/.oh-my-zsh"

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

ZSH_THEME="agnoster"

# Prevent zsh-autocomplete from appending semicolons or symbols at the end of lines
zstyle ':autocomplete:*' config 'no-multiline'

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  fast-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# ---------------------------------------------------------------------------
# Harbor
# ---------------------------------------------------------------------------
# /usr/local/bin holds the harbor shim and must stay ahead of the real binary in
# /root/.local/bin. See /usr/local/bin/harbor for why the shim exists.
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

# Jump to the mirror of /workspace at its real host path. Rarely needed - the shim
# handles it - but useful when driving docker by hand with host-side paths.
cdw() { cd "${HOST_WORKSPACE:-/workspace}"; }

alias harbor-jobs='ls -1t /workspace/jobs 2>/dev/null | head'

# ---------------------------------------------------------------------------
# atuin (shell history)
# ---------------------------------------------------------------------------
[ -s "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"
command -v atuin >/dev/null 2>&1 && eval "$(atuin init zsh)"
