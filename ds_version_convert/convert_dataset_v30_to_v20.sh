#!/usr/bin/env bash
set -euo pipefail

REPO_ID="${1:?Error: repo_id required, e.g. lerobot/pusht}"
ROOT="${2:?Error: root directory required}"

echo "Converting $REPO_ID from v3.0 → v2.1..."
uv run convert_dataset_v30_to_v21.py \
    --repo-id="$REPO_ID" \
    --root="$ROOT"

echo "Converting $REPO_ID from v2.1 → v2.0..."
uv run convert_dataset_v21_to_v20.py \
    --repo-id="$REPO_ID" \
    --root="$ROOT"

echo "Conversion complete: $REPO_ID"
