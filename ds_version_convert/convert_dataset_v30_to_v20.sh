#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_BASE="${1:?Error: source base directory required}"
DST_BASE="${2:?Error: destination base directory required}"
JOBS="${3:-1}"

trap 'kill 0' INT TERM

mkdir -p "$DST_BASE"

_convert_one() {
    local SRC="$1" DST="$2" REPO_ID="$3"
    if [[ -f "$DST/meta/info.json" ]] && \
       grep -q '"codebase_version": "v2.0"' "$DST/meta/info.json"; then
        echo "Skipping $REPO_ID (already complete)"
        return 0
    fi
    if ! uv run "$SCRIPT_DIR/v30_to_v21/convert_dataset_v30_to_v21.py" \
            --repo-id="$REPO_ID" --root="$SRC" --output="$DST" || \
       ! uv run "$SCRIPT_DIR/v21_to_v20/convert_dataset_v21_to_v20.py" \
            --repo-id="$REPO_ID" --root="$DST"; then
        echo "ERROR: conversion failed for $REPO_ID" >&2
        return 0
    fi
    echo "Conversion complete: $REPO_ID -> $DST"
}

running=0
while IFS= read -r SRC; do
    name="$(basename "$SRC")"
    _convert_one "$SRC" "$DST_BASE/$name" "$(basename "$SRC_BASE")/$name" < /dev/null &
    running=$(( running + 1 ))
    if (( running >= JOBS )); then
        wait -n
        running=$(( running - 1 ))
    fi
done < <(find "$SRC_BASE" -maxdepth 1 -mindepth 1 -type d | sort)
wait
