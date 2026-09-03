#!/usr/bin/env bash
# Re-apply this template's .devcontainer/ to an existing project, showing what would
# change first. The project's devcontainer.env (secrets) is never touched.
#
#   Usage: sync-template.sh <project-dir> [--yes]
set -euo pipefail

template="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

target="${1:-}"
if [ -z "$target" ] || [ ! -d "$target" ]; then
    echo "usage: $(basename "$0") <project-dir> [--yes]" >&2
    exit 2
fi
target="$(cd "$target" && pwd)"
assume_yes=0
[ "${2:-}" = "--yes" ] && assume_yes=1

if [ ! -d "$target/.devcontainer" ]; then
    echo "note: $target has no .devcontainer yet; it will be created."
else
    echo "Changes that would be applied to $target/.devcontainer:"
    echo ""
    diff -ru --exclude=devcontainer.env \
        "$target/.devcontainer" "$template/.devcontainer" || true
    echo ""
fi

if [ "$assume_yes" -eq 0 ]; then
    read -r -p "Apply? [y/N] " reply
    case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# --exclude keeps the project's secrets file; everything else is overwritten so the
# template stays the single source of truth.
mkdir -p "$target/.devcontainer"
for f in "$template"/.devcontainer/* "$template"/.devcontainer/.[!.]*; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "devcontainer.env" ] && continue
    cp -r "$f" "$target/.devcontainer/$base"
done

# Root-level helper script travels with the template, so refresh it in place.
cp "$template/stop-devcontainer.sh" "$target/stop-devcontainer.sh"
chmod +x "$target/stop-devcontainer.sh"

# Create task/ if this project predates the convention. Never touch tasks already
# in there - only seed the directory and its README when it is missing.
if [ ! -d "$target/task" ]; then
    cp -r "$template/task" "$target/"
    echo "Created $target/task (new convention: Harbor tasks live here)."
fi

echo "Applied. Rebuild the container, then re-verify:"
echo "  .devcontainer/verify-setup.sh     # inside the container; must print PASS"
