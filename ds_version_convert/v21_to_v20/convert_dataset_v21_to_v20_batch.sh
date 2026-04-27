#!/usr/bin/env bash
# Usage: convert_dataset_v21_to_v20_batch.sh <src_base> <dst_base> [jobs]
#
# Batch-convert LeRobot v2.1 datasets (*.tar.gz) to v2.0, extracting them
# into <dst_base> while mirroring the subdirectory structure of <src_base>.
# Already-converted destinations are skipped automatically.
#
# Arguments:
#   src_base   Directory tree containing *.tar.gz datasets (searched recursively)
#   dst_base   Output root; datasets land at dst_base/<rel_path_without_.tar.gz>/
#   jobs       Parallel worker count (default: 4)
#
# Example:
#   bash convert_dataset_v21_to_v20_batch.sh \
#     /data/sim_updated /output/sim_updated 8
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_BASE="${1:?Error: source base directory required}"
DST_BASE="${2:?Error: destination base directory required}"
JOBS="${3:-4}"
CONVERT_SCRIPT="$SCRIPT_DIR/convert_dataset_v21_to_v20.py"

trap 'kill 0' INT TERM

mkdir -p "$DST_BASE"

_convert_one() {
    local TARBALL="$1" SRC_BASE="$2" DST_BASE="$3" CONVERT_SCRIPT="$4"
    local REL_PATH BASENAME DST_DIR
    REL_PATH="${TARBALL#"$SRC_BASE"/}"           # e.g. articulation_tasks/franka/foo.tar.gz
    BASENAME="$(basename "$REL_PATH" .tar.gz)"   # e.g. foo
    DST_DIR="$DST_BASE/${REL_PATH%.tar.gz}"      # e.g. $DST_BASE/articulation_tasks/franka/foo

    if [[ -f "$DST_DIR/meta/info.json" ]] && \
       grep -q '"codebase_version": "v2.0"' "$DST_DIR/meta/info.json"; then
        echo "[SKIP] $REL_PATH (already v2.0)"
        return 0
    fi

    local TMPDIR
    TMPDIR="$(mktemp -d -p "$DST_BASE")"

    mkdir -p "$(dirname "$DST_DIR")"
    tar -xzf "$TARBALL" -C "$TMPDIR"

    if ! uv run "$CONVERT_SCRIPT" \
            --repo-id="$BASENAME" \
            --root="$TMPDIR/$BASENAME"; then
        echo "[ERROR] $REL_PATH" >&2
        rm -rf "$TMPDIR"
        return 1
    fi

    rm -rf "$DST_DIR"
    mv "$TMPDIR/$BASENAME" "$DST_DIR"
    rm -rf "$TMPDIR"

    echo "[DONE] $REL_PATH -> $DST_DIR"
}

export -f _convert_one

running=0
while IFS= read -r TARBALL; do
    _convert_one "$TARBALL" "$SRC_BASE" "$DST_BASE" "$CONVERT_SCRIPT" </dev/null &
    running=$(( running + 1 ))
    if (( running >= JOBS )); then
        wait -n
        running=$(( running - 1 ))
    fi
done < <(find "$SRC_BASE" -name "*.tar.gz" | sort)
wait

echo "All done."
