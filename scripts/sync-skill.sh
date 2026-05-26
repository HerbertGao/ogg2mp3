#!/bin/bash
# Sync the SOT SKILL.md to all host adapter copies.
# Run this whenever packaging/skill/ogg2mp3/SKILL.md changes.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOT="$ROOT/packaging/skill/ogg2mp3/SKILL.md"

[[ -f "$SOT" ]] || { echo "SOT missing: $SOT" >&2; exit 1; }

TARGETS=(
    "$ROOT/packaging/claude-code/skills/ogg2mp3/SKILL.md"
    "$ROOT/packaging/codex/skills/ogg2mp3/SKILL.md"
)

for t in "${TARGETS[@]}"; do
    mkdir -p "$(dirname "$t")"
    if cmp -s "$SOT" "$t" 2>/dev/null; then
        echo "unchanged: ${t#$ROOT/}"
    else
        cp "$SOT" "$t"
        echo "synced:    ${t#$ROOT/}"
    fi
done
