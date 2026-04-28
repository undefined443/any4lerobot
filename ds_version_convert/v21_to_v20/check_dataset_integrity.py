"""
Usage:
    uv run check_dataset_integrity.py <dst_base> [--src <src_base>]

Checks every LeRobot dataset under <dst_base> (skipping tmp.* directories):
  - codebase_version == v2.0
  - meta/stats.json exists
  - data/ directory exists

If --src is provided, also reports which source *.tar.gz packages have no
corresponding converted output under <dst_base>.
"""
import argparse
import json
from pathlib import Path


def is_tmp(path: Path) -> bool:
    return any(p.name.startswith("tmp.") for p in path.parents) or path.name.startswith("tmp.")


def find_datasets(base: Path) -> list[Path]:
    return [
        p.parent.parent
        for p in base.rglob("meta/info.json")
        if not is_tmp(p)
    ]


def check_dataset(ds_dir: Path) -> dict:
    info_path = ds_dir / "meta" / "info.json"
    try:
        version = json.loads(info_path.read_text())["codebase_version"]
    except Exception as e:
        version = f"ERROR({e})"

    return {
        "path": ds_dir,
        "version": version,
        "has_stats": (ds_dir / "meta" / "stats.json").is_file(),
        "has_data": (ds_dir / "data").is_dir(),
    }


def check_missing(src_base: Path, dst_base: Path) -> list[str]:
    missing = []
    for tarball in sorted(src_base.rglob("*.tar.gz")):
        rel = tarball.relative_to(src_base).with_suffix("").with_suffix("")
        dst_dir = dst_base / rel
        if not dst_dir.exists():
            missing.append(str(rel))
            continue
        # Has any meta/info.json (single or multi-sub-dataset)
        if not any(dst_dir.rglob("meta/info.json")):
            missing.append(str(rel))
    return missing


def main():
    parser = argparse.ArgumentParser(description="Check LeRobot dataset integrity.")
    parser.add_argument("dst_base", type=Path)
    parser.add_argument("--src", type=Path, default=None, dest="src_base")
    args = parser.parse_args()

    datasets = find_datasets(args.dst_base)

    ok = wrong_version = missing_stats = missing_data = 0
    bad = []

    for ds_dir in sorted(datasets):
        r = check_dataset(ds_dir)
        is_ok = r["version"] == "v2.0" and r["has_stats"] and r["has_data"]
        if is_ok:
            ok += 1
        else:
            bad.append(r)
            if r["version"] != "v2.0":
                wrong_version += 1
            if not r["has_stats"]:
                missing_stats += 1
            if not r["has_data"]:
                missing_data += 1

    print(f"{'='*50}")
    print(f"{'正常':<20} {ok}")
    print(f"{'版本非 v2.0':<18} {wrong_version}")
    print(f"{'缺 stats.json':<18} {missing_stats}")
    print(f"{'缺 data/':<20} {missing_data}")
    print(f"{'='*50}")

    if bad:
        print("\n[异常数据集]")
        for r in bad:
            rel = r["path"].relative_to(args.dst_base)
            flags = []
            if r["version"] != "v2.0":
                flags.append(f"version={r['version']}")
            if not r["has_stats"]:
                flags.append("no stats.json")
            if not r["has_data"]:
                flags.append("no data/")
            print(f"  {rel}  ({', '.join(flags)})")

    if args.src_base:
        missing = check_missing(args.src_base, args.dst_base)
        print(f"\n[源包未转换] {len(missing)} 个")
        for m in missing:
            print(f"  {m}")


if __name__ == "__main__":
    main()
