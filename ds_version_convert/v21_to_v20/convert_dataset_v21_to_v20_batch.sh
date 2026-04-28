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

    # Detect structure: single dataset vs multi-sub-dataset (meta/info.json at depth 2 vs 3+)
    local FIRST_META META_DEPTH IS_MULTI=0
    FIRST_META="$(tar -tzf "$TARBALL" 2>/dev/null | grep '/meta/info\.json$' | head -1)"
    META_DEPTH="$(echo "$FIRST_META" | tr -cd '/' | wc -c)"
    [[ "$META_DEPTH" -gt 2 ]] && IS_MULTI=1

    if [[ "$IS_MULTI" -eq 0 ]]; then
        if [[ -f "$DST_DIR/meta/info.json" ]] && \
           grep -q '"codebase_version": "v2.0"' "$DST_DIR/meta/info.json"; then
            echo "[SKIP] $REL_PATH (already v2.0)"
            return 0
        fi
    else
        # Multi-sub-dataset: skip if every sub-dataset is already v2.0
        local all_done=1
        while IFS= read -r subname; do
            [[ -z "$subname" ]] && continue
            grep -q '"codebase_version": "v2.0"' "$DST_DIR/$subname/meta/info.json" 2>/dev/null || { all_done=0; break; }
        done < <(tar -tzf "$TARBALL" 2>/dev/null | awk -F'/' 'NF>=3{print $2}' | sort -u)
        if [[ "$all_done" -eq 1 ]]; then
            echo "[SKIP] $REL_PATH (all sub-datasets already v2.0)"
            return 0
        fi
    fi

    local TMPDIR
    TMPDIR="$(mktemp -d -p "$DST_BASE")"
    mkdir -p "$(dirname "$DST_DIR")"
    tar -xzf "$TARBALL" -C "$TMPDIR"

    if [[ "$IS_MULTI" -eq 0 ]]; then
        local EXTRACTED_DIR
        EXTRACTED_DIR="$(find "$TMPDIR" -mindepth 1 -name "meta" -type d | head -1 | xargs dirname)"

        if [[ -z "$EXTRACTED_DIR" ]]; then
            echo "[ERROR] $REL_PATH: could not find meta/ directory after extraction" >&2
            rm -rf "$TMPDIR"
            return 1
        fi

        if ! uv run "$CONVERT_SCRIPT" --repo-id="$BASENAME" --root="$EXTRACTED_DIR"; then
            echo "[ERROR] $REL_PATH" >&2
            rm -rf "$TMPDIR"
            return 1
        fi

        rm -rf "$DST_DIR"
        mv "$EXTRACTED_DIR" "$DST_DIR"
        rm -rf "$TMPDIR"
        echo "[DONE] $REL_PATH -> $DST_DIR"
    else
        # Multi-sub-dataset: convert each immediate subdirectory independently
        local sub_errors=0
        mkdir -p "$DST_DIR"
        while IFS= read -r SUBDIR; do
            local SUBNAME DST_SUBDIR
            SUBNAME="$(basename "$SUBDIR")"
            DST_SUBDIR="$DST_DIR/$SUBNAME"

            if [[ -f "$DST_SUBDIR/meta/info.json" ]] && \
               grep -q '"codebase_version": "v2.0"' "$DST_SUBDIR/meta/info.json"; then
                echo "[SKIP] $REL_PATH/$SUBNAME (already v2.0)"
                continue
            fi

            if ! uv run "$CONVERT_SCRIPT" --repo-id="$SUBNAME" --root="$SUBDIR"; then
                echo "[ERROR] $REL_PATH/$SUBNAME" >&2
                sub_errors=$(( sub_errors + 1 ))
                continue
            fi

            rm -rf "$DST_SUBDIR"
            mv "$SUBDIR" "$DST_SUBDIR"
            echo "[DONE] $REL_PATH/$SUBNAME -> $DST_SUBDIR"
        done < <(find "$TMPDIR/$BASENAME" -mindepth 1 -maxdepth 1 -type d | sort)

        rm -rf "$TMPDIR"
        [[ "$sub_errors" -gt 0 ]] && return 1
    fi
}

export -f _convert_one

running=0
while IFS= read -r TARBALL; do
    _convert_one "$TARBALL" "$SRC_BASE" "$DST_BASE" "$CONVERT_SCRIPT" </dev/null &
    running=$(( running + 1 ))
    if (( running >= JOBS )); then
        wait -n || true
        running=$(( running - 1 ))
    fi
done < <(find "$SRC_BASE" -name "*.tar.gz" | sort)
wait

echo "All done."
