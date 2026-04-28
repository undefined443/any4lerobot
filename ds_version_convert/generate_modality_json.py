#!/usr/bin/env python3
"""
Generate modality.json for LeRobot v2.0 datasets from info.json

This script creates a modality.json file by analyzing the features defined in info.json.
It maps the feature dimensions to action/state/video modalities with correct start/end indices.

Usage:
    python3 generate_modality_json.py /path/to/dataset

    # Or for multiple datasets:
    python3 generate_modality_json.py /path/to/dataset1 /path/to/dataset2 ...
"""

import argparse
import json
from pathlib import Path
from typing import Any, Dict


def extract_modality_from_info(info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract modality configuration from dataset info.json

    Args:
        info: Dictionary loaded from info.json

    Returns:
        Dictionary with action/state/video modality definitions
    """
    features = info.get("features", {})

    modality = {"state": {}, "action": {}, "video": {}}

    # Process action features
    action_idx = 0
    for feature_name in sorted(features.keys()):
        if not feature_name.startswith("action"):
            continue

        feature_info = features[feature_name]
        shape = feature_info.get("shape", [1])

        # Handle nested lists for shape
        if isinstance(shape, list):
            dim = shape[0] if shape else 1
        else:
            dim = 1

        # Extract subkey name from feature_name
        # e.g., "action.joint.position" -> "joint_position"
        # or "actions.ee_to_armbase_pose" -> "ee_to_armbase_pose"
        parts = feature_name.replace("action.", "").replace("actions.", "").split(".")
        subkey = "_".join(parts)

        modality["action"][subkey] = {"start": action_idx, "end": action_idx + dim}
        action_idx += dim

    # Process state features
    state_idx = 0
    for feature_name in sorted(features.keys()):
        # Match observation.states.* or observation.state.* patterns
        if not (
            feature_name.startswith("observation.state")
            or (
                feature_name.startswith("observation.")
                and "images" not in feature_name
                and "depth" not in feature_name
                and "action" not in feature_name
            )
        ):
            continue

        feature_info = features[feature_name]
        shape = feature_info.get("shape", [1])

        if isinstance(shape, list):
            dim = shape[0] if shape else 1
        else:
            dim = 1

        # Extract subkey name
        parts = (
            feature_name.replace("observation.states.", "")
            .replace("observation.state.", "")
            .split(".")
        )
        subkey = "_".join(parts)

        modality["state"][subkey] = {"start": state_idx, "end": state_idx + dim}
        state_idx += dim

    # Process video features
    for feature_name in sorted(features.keys()):
        if not feature_name.startswith("images.") and not feature_name.startswith(
            "video."
        ):
            continue

        # Extract camera/video key name
        # e.g., "images.rgb.head" -> "head", or "video.image_side_0" -> "image_side_0"
        parts = (
            feature_name.replace("images.", "")
            .replace("images", "")
            .replace("video.", "")
            .split(".")
        )
        subkey = parts[-1] if parts[-1] else "_".join(parts)

        modality["video"][subkey] = {"original_key": feature_name}

    return modality


def generate_modality_json(dataset_path: Path, overwrite: bool = False) -> bool:
    """
    Generate modality.json for a dataset

    Args:
        dataset_path: Path to the dataset root
        overwrite: Whether to overwrite existing modality.json

    Returns:
        True if successful, False otherwise
    """
    dataset_path = Path(dataset_path)
    info_json_path = dataset_path / "meta" / "info.json"
    modality_json_path = dataset_path / "meta" / "modality.json"

    # Validate input
    if not dataset_path.exists():
        print(f"✗ Dataset path not found: {dataset_path}")
        return False

    if not info_json_path.exists():
        print(f"✗ info.json not found in {info_json_path}")
        return False

    if modality_json_path.exists() and not overwrite:
        print(f"⚠ modality.json already exists: {modality_json_path}")
        print("  Use --overwrite to replace it")
        return False

    # Load info.json and generate modality
    try:
        with open(info_json_path) as f:
            info = json.load(f)

        modality = extract_modality_from_info(info)

        # Write modality.json
        with open(modality_json_path, "w") as f:
            json.dump(modality, f, indent=4)

        # Print summary
        action_dim = modality["action"][-1]["end"] if modality["action"] else 0
        state_dim = modality["state"][-1]["end"] if modality["state"] else 0

        print(f"✓ Generated: {modality_json_path}")
        print(f"  - Action dimensions: {action_dim}D")
        print(f"  - State dimensions: {state_dim}D")
        print(f"  - Video cameras: {len(modality['video'])}")
        if modality["action"]:
            action_keys = list(modality["action"].keys())[:3]
            print(
                f"  - Action keys: {action_keys}{'...' if len(modality['action']) > 3 else ''}"
            )
        if modality["state"]:
            state_keys = list(modality["state"].keys())[:3]
            print(
                f"  - State keys: {state_keys}{'...' if len(modality['state']) > 3 else ''}"
            )

        return True

    except Exception as e:
        print(f"✗ Error processing {dataset_path}: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "datasets", nargs="+", help="Path(s) to dataset root directory/directories"
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing modality.json files",
    )

    args = parser.parse_args()

    # Process each dataset
    success_count = 0
    for dataset_path in args.datasets:
        if generate_modality_json(Path(dataset_path), args.overwrite):
            success_count += 1
        print()

    # Summary
    total = len(args.datasets)
    print(f"Summary: {success_count}/{total} dataset(s) processed successfully")

    return 0 if success_count == total else 1


if __name__ == "__main__":
    exit(main())
