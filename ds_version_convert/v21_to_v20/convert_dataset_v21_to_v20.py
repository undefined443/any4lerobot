import argparse
import json
from pathlib import Path

import jsonlines
import numpy as np

from lerobot.datasets.io_utils import write_info, write_stats
from lerobot.datasets.utils import LEGACY_EPISODES_STATS_PATH, STATS_PATH
from lerobot.utils.constants import HF_LEROBOT_HOME

V20 = "v2.0"
INFO_PATH = "meta/info.json"


def _aggregate_stats(episodes_stats: list[dict]) -> dict[str, dict[str, np.ndarray]]:
    all_stats = [ep["stats"] for ep in episodes_stats]
    result = {}
    for key in all_stats[0]:
        ep_key_stats = [s[key] for s in all_stats]
        counts = np.array([s["count"][0] for s in ep_key_stats], dtype=float)
        total_count = counts.sum()

        mins = np.array([s["min"] for s in ep_key_stats])
        maxs = np.array([s["max"] for s in ep_key_stats])
        means = np.array([s["mean"] for s in ep_key_stats])
        stds = np.array([s["std"] for s in ep_key_stats])

        global_min = mins.min(axis=0)
        global_max = maxs.max(axis=0)

        w = (counts / total_count).reshape([-1] + [1] * (means.ndim - 1))
        global_mean = (means * w).sum(axis=0)

        diff = means - global_mean
        n = counts.reshape([-1] + [1] * (stds.ndim - 1))
        global_std = np.sqrt((n * (stds**2 + diff**2)).sum(axis=0) / total_count)

        result[key] = {
            "min": global_min,
            "max": global_max,
            "mean": global_mean,
            "std": global_std,
        }
    return result


def convert_dataset(
    repo_id: str,
    root: str | None = None,
    push_to_hub: bool = False,
    delete_old_stats: bool = False,
    branch: str | None = None,
):
    root = Path(root) if root is not None else HF_LEROBOT_HOME / repo_id

    episodes_stats_path = root / LEGACY_EPISODES_STATS_PATH
    with jsonlines.open(episodes_stats_path) as reader:
        episodes_stats = list(reader)

    stats = _aggregate_stats(episodes_stats)

    if (root / STATS_PATH).is_file():
        (root / STATS_PATH).unlink()
    write_stats(stats, root)

    info_path = root / INFO_PATH
    with open(info_path) as f:
        info = json.load(f)
    info["codebase_version"] = V20
    write_info(info, root)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--repo-id",
        type=str,
        required=True,
    )
    parser.add_argument(
        "--root",
        type=str,
        default=None,
        help="Path to the local dataset root directory.",
    )
    parser.add_argument("--push-to-hub", action="store_true")
    parser.add_argument("--delete-old-stats", action="store_true")
    parser.add_argument("--branch", type=str, default=None)

    args = parser.parse_args()
    convert_dataset(**vars(args))
