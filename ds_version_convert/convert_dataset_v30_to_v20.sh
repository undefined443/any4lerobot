#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_BASE="${1:?Error: source base directory required}"
DST_BASE="${2:?Error: destination base directory required}"

mkdir -p "$DST_BASE"

for SRC in "$SRC_BASE"/*/; do
    name="$(basename "$SRC")"
    DST="$DST_BASE/$name"
    REPO_ID="$(basename "$SRC_BASE")/$name"

    echo "Converting $REPO_ID from v3.0 -> v2.1 ..."
    uv run "$SCRIPT_DIR/v30_to_v21/convert_dataset_v30_to_v21.py" \
        --repo-id="$REPO_ID" \
        --root="$SRC" \
        --output="$DST"

    echo "Converting $REPO_ID from v2.1 -> v2.0 ..."
    uv run "$SCRIPT_DIR/v21_to_v20/convert_dataset_v21_to_v20.py" \
        --repo-id="$REPO_ID" \
        --root="$DST"

    echo "Conversion complete: $REPO_ID -> $DST"
done
