#!/usr/bin/env bash
# Prove this container can actually run a Harbor trial end to end.
#
# RUN THIS INSIDE THE CONTAINER, from /workspace. It scaffolds a throwaway task whose
# test makes a real assertion, runs it with the `oracle` agent (which just executes the
# reference solution), and checks the reward came back as 1.0.
#
# This is the check that matters after any rebuild or template sync: it exercises the
# whole solution -> environment -> verifier -> reward.txt path, which is exactly what
# breaks when the mirror mount or the harbor shim is not working. A reward of 0 with a
# RewardFileNotFoundError is the signature of that failure.
set -euo pipefail

work="$(mktemp -d /workspace/.harbor-verify-XXXXXX)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

echo "Harbor devcontainer self-check"
echo ""

printf '  %-18s' "harbor"
harbor --version || { echo "FAIL"; exit 1; }

printf '  %-18s' "shim on PATH"
if [ "$(command -v harbor)" = "/usr/local/bin/harbor" ]; then
    echo "ok (/usr/local/bin/harbor)"
else
    echo "FAIL - resolves to $(command -v harbor), not the shim"
    exit 1
fi

printf '  %-18s' "host docker"
docker version --format '{{.Server.Version}}' || { echo "FAIL"; exit 1; }

printf '  %-18s' "mirror mount"
if [ -n "${HOST_WORKSPACE:-}" ] && [ -d "${HOST_WORKSPACE:-/nonexistent}" ]; then
    probe="$(mktemp -p /workspace .probe-XXXXXX)"
    if [ -f "${HOST_WORKSPACE}/$(basename "$probe")" ]; then echo "ok"; else echo "FAIL"; rm -f "$probe"; exit 1; fi
    rm -f "$probe"
else
    echo "FAIL - HOST_WORKSPACE unset or not mounted"
    exit 1
fi

echo ""
echo "  Running an oracle trial (this builds a small image; ~1 minute)..."
echo ""

cd "$work"
harbor init -t verify --org selfcheck --description "devcontainer self-check" >/dev/null

cat > verify/solution/solve.sh <<'EOF'
#!/bin/bash
printf 'harbor-ok' > /app/answer.txt
EOF

cat > verify/tests/test_outputs.py <<'EOF'
from pathlib import Path


def test_answer_file_written():
    p = Path("/app/answer.txt")
    assert p.exists(), "/app/answer.txt was not created"
    assert p.read_text() == "harbor-ok"
EOF

harbor run -p verify -a oracle 2>&1 | tail -20

reward_file="$(find "$work/jobs" -name reward.txt 2>/dev/null | head -1)"
echo ""
if [ -n "$reward_file" ] && [ -s "$reward_file" ] && [ "$(tr -d '[:space:]' < "$reward_file")" = "1" ]; then
    echo "PASS - reward 1.0 collected from $(basename "$(dirname "$reward_file")")/reward.txt"
    echo "       The mirror mount and the harbor shim are working."
    exit 0
fi

echo "FAIL - no reward of 1.0 came back."
if [ -z "$reward_file" ]; then
    echo "       reward.txt was never collected. This is the mirror-mount / shim failure:"
    echo "       the host daemon resolved a /workspace path that only exists in here."
    echo "       Check for a stray root-owned /workspace directory ON THE HOST."
fi
echo "       See the Troubleshooting section of the template README."
exit 1
