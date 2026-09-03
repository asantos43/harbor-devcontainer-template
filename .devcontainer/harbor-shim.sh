#!/usr/bin/env bash
# Path-translating wrapper around the real `harbor` binary.
#
# The devcontainer talks to the HOST docker daemon over a bind-mounted socket, so the
# task containers Harbor creates are siblings of this one, not children. That daemon
# resolves bind-mount sources against the HOST filesystem, and Harbor bind-mounts its
# jobs directory into every task container to collect /logs (the verifier writes the
# trial reward to /logs/verifier/reward.txt through that mount).
#
# /workspace exists only inside this container. If Harbor ran with cwd=/workspace it
# would hand "/workspace/jobs/..." to the host daemon, which would silently create an
# empty root-owned directory at that path on the host -- the reward file would land
# somewhere Harbor cannot read it and EVERY TRIAL WOULD SCORE 0.
#
# $HOST_WORKSPACE is the same directory as /workspace, mounted a second time at the
# absolute path the host knows it by. Re-entering it here (and rewriting /workspace
# arguments) makes every path Harbor derives valid on both sides of the socket.
set -euo pipefail

real="${HOME}/.local/bin/harbor"

if [ ! -x "$real" ]; then
    echo "harbor-shim: real harbor binary not found at $real" >&2
    exit 127
fi

# Outside the devcontainer (or if the mirror mount is missing) there is nothing to
# translate; behave exactly like the real binary.
if [ -z "${HOST_WORKSPACE:-}" ] || [ ! -d "${HOST_WORKSPACE:-/nonexistent}" ]; then
    exec "$real" "$@"
fi

case "$PWD" in
    /workspace) cd "$HOST_WORKSPACE" ;;
    /workspace/*) cd "${HOST_WORKSPACE}${PWD#/workspace}" ;;
esac

args=()
for a in "$@"; do
    case "$a" in
        /workspace) args+=("$HOST_WORKSPACE") ;;
        /workspace/*) args+=("${HOST_WORKSPACE}${a#/workspace}") ;;
        *) args+=("$a") ;;
    esac
done

exec "$real" ${args[@]+"${args[@]}"}
