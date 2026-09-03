#!/usr/bin/env bash
# Bump the pinned toolchain to the latest published versions.
#
# RUN THIS ON THE HOST, not inside the devcontainer: it needs the `devcontainer` CLI
# to refresh the feature lockfile, and the rebuild afterwards has to happen from
# outside the container being rebuilt.
#
#   Usage: .devcontainer/update-toolchain.sh [--dry-run]
set -euo pipefail

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="$(cd "$here/.." && pwd)"
versions="$here/versions.env"

for tool in curl jq; do
    command -v "$tool" >/dev/null || { echo "error: $tool is required" >&2; exit 1; }
done

current() { grep -E "^$1=" "$versions" | cut -d= -f2-; }

set_version() {
    local key="$1" new="$2" old
    old="$(current "$key")"
    if [ "$old" = "$new" ]; then
        printf '  %-16s %s (unchanged)\n' "$key" "$old"
        return
    fi
    printf '  %-16s %s -> %s\n' "$key" "$old" "$new"
    [ "$dry_run" -eq 1 ] || sed -i -E "s|^${key}=.*|${key}=${new}|" "$versions"
}

echo "Querying latest versions..."

harbor_latest="$(curl -fsS https://pypi.org/pypi/harbor/json | jq -r .info.version)"
uv_latest="$(curl -fsS https://api.github.com/repos/astral-sh/uv/releases/latest \
             | jq -r .tag_name | sed 's/^v//')"

# Harbor's own floor, so a PYTHON_VERSION bump can never drop below what it supports.
harbor_python="$(curl -fsS https://pypi.org/pypi/harbor/json | jq -r .info.requires_python)"

echo ""
echo "versions.env:"
set_version HARBOR_VERSION "$harbor_latest"
set_version UV_VERSION     "$uv_latest"
echo "  (harbor requires_python: ${harbor_python}; PYTHON_VERSION is $(current PYTHON_VERSION),"
echo "   bump it by hand in versions.env if you want a newer interpreter)"

echo ""
echo "Dev container features:"
if command -v devcontainer >/dev/null; then
    devcontainer outdated --workspace-folder "$project" || true
    if [ "$dry_run" -eq 0 ]; then
        devcontainer upgrade --workspace-folder "$project" \
            && echo "  devcontainer-lock.json refreshed"
    fi
else
    echo "  warning: devcontainer CLI not found; skipped the feature lockfile" >&2
fi

echo ""
if [ "$dry_run" -eq 1 ]; then
    echo "Dry run - nothing written."
else
    if git -C "$project" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$project" --no-pager diff -- .devcontainer || true
    fi
    echo ""
    echo "Next: rebuild, verify, then commit."
    echo "  devcontainer build --workspace-folder \"$project\"   # or VS Code: Rebuild Container"
    echo "  harbor run -p <task> -a oracle                      # must still report reward 1.0"
fi
