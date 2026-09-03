#!/usr/bin/env bash
# Runs on the HOST, before the container is created -- the only hook early enough to
# satisfy things the container-create arguments depend on.
#
# devcontainer.json passes --env-file .devcontainer/devcontainer.env in runArgs, and
# docker refuses to start a container when that file is missing. Creating it here
# means a fresh clone comes up without anyone having to touch a secrets file first.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
envfile="$here/devcontainer.env"

if [ ! -f "$envfile" ]; then
    cat > "$envfile" <<'TEMPLATE'
# Secrets for this devcontainer, passed with docker --env-file. Gitignored.
# One KEY=value per line, no quotes, no export.
#
# Keys already forwarded from your host shell by devcontainer.json's remoteEnv
# (ANTHROPIC_API_KEY, OPENAI_API_KEY) do not need to be repeated here.
#
# ANTHROPIC_API_KEY=sk-ant-...
# OPENAI_API_KEY=sk-...
TEMPLATE
    echo "initialize: created $envfile"
fi
