#!/usr/bin/env bash
# Scaffold a new Harbor project from this template.
#
#   Usage: new-harbor-project.sh <name> [parent-dir]
#
# Default parent is ~/dev/projects/data_annotation/harbor-projects.
set -euo pipefail

template="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

name="${1:-}"
if [ -z "$name" ]; then
    echo "usage: $(basename "$0") <name> [parent-dir]" >&2
    exit 2
fi
parent="${2:-$HOME/dev/projects/data_annotation/harbor-projects}"
target="$parent/$name"

if [ -e "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
    echo "error: $target already exists and is not empty" >&2
    exit 1
fi

mkdir -p "$target"
cp -r "$template/.devcontainer" "$target/"
# task/ is where every Harbor task in the project lives; it ships with a README so
# the convention travels with the project and git actually tracks the directory.
cp -r "$template/task" "$target/"
cp "$template/stop-devcontainer.sh" "$target/"
chmod +x "$target/stop-devcontainer.sh"
cp "$template/template-gitignore" "$target/.gitignore"
sed "s|{{PROJECT_NAME}}|$name|g" "$template/project-README.md" > "$target/README.md"

git -C "$target" rev-parse --git-dir >/dev/null 2>&1 || git -C "$target" init -q

echo "Created $target"
echo ""
echo "Next:"
echo "  code \"$target\"                  # then: Reopen in Container"
echo "  harbor init -t my-task -o task    # inside the container, from /workspace"
echo "  harbor run  -p task/my-task -a oracle"
