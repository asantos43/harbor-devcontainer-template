#!/usr/bin/env bash
# Stop this project's dev container.
#
# RUN THIS ON THE HOST, from anywhere - the script locates the container from its own
# directory, so `./stop-devcontainer.sh` and an absolute path both work.
#
# The container is found by the `devcontainer.local_folder` label the devcontainer CLI
# stamps on it, which is exact even if the --name in devcontainer.json is changed. The
# name is only a fallback for a container started some other way.
#
#   Usage: stop-devcontainer.sh [--remove]
#
#     --remove   also delete the container, so the next start recreates it from the
#                image and re-runs postCreateCommand. The workspace is a bind mount,
#                so nothing in the project is lost either way.
set -euo pipefail

project="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
name="$(basename "$project")-devcontainer"

remove=0
case "${1:-}" in
    --remove|-r) remove=1 ;;
    "") ;;
    *) echo "usage: $(basename "$0") [--remove]" >&2; exit 2 ;;
esac

# Stopping the container you are running inside kills this shell mid-script, and you
# would never see the output. Refuse instead of half-doing it.
if [ -f /.dockerenv ] || [ -n "${REMOTE_CONTAINERS:-}" ]; then
    # $project is a container path in here; HOST_WORKSPACE is the same directory as
    # the host knows it, which is the path worth printing.
    host_path="${HOST_WORKSPACE:-$project}"
    echo "error: this stops the dev container, so it has to run on the HOST, not inside it." >&2
    echo "       Open a terminal on your machine and run:" >&2
    echo "         $host_path/$(basename "$0")" >&2
    exit 1
fi

command -v docker >/dev/null || { echo "error: docker not found" >&2; exit 1; }

container="$(docker ps -q --filter "label=devcontainer.local_folder=$project" | head -1)"
if [ -z "$container" ]; then
    container="$(docker ps -q --filter "name=^${name}$" | head -1)"
fi

if [ -z "$container" ]; then
    # Not running. Say whether it exists but is stopped, or does not exist at all.
    stopped="$(docker ps -aq --filter "label=devcontainer.local_folder=$project" \
               --filter "status=exited" | head -1)"
    [ -z "$stopped" ] && stopped="$(docker ps -aq --filter "name=^${name}$" | head -1)"

    if [ -n "$stopped" ]; then
        if [ "$remove" -eq 1 ]; then
            docker rm "$stopped" >/dev/null
            echo "Already stopped; removed $(echo "$stopped" | cut -c1-12)."
        else
            echo "Already stopped."
        fi
    else
        echo "No dev container for this project."
    fi
    exit 0
fi

label="$(docker inspect --format '{{.Name}}' "$container" | sed 's|^/||')"
docker stop "$container" >/dev/null
echo "Stopped $label."

if [ "$remove" -eq 1 ]; then
    docker rm "$container" >/dev/null
    echo "Removed $label."
fi

echo ""
echo "Start it again with VS Code's Reopen in Container, or:"
echo "  devcontainer up --workspace-folder \"$project\""
