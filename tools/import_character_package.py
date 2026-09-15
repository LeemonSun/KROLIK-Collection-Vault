from __future__ import annotations

import argparse
from pathlib import Path

from character_import import build_character_runtime_package
from import_integrity import ImportIntegrityError, validate_built_import
from rig_edit import load_joint_overrides
from runtime_package_integrity import RuntimePackageIntegrityError, seal_built_runtime_package


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Import a character image into immutable KROLIK assets and build a runtime package"
    )
    parser.add_argument("source", help="PNG/JPEG/WebP/BMP character image")
    parser.add_argument("--project-root", default=".", help="Project/workspace root for imports and exports")
    parser.add_argument("--character-id", required=True, help="Stable character identifier")
    parser.add_argument("--name", default=None, help="Display name; defaults to character id")
    parser.add_argument(
        "--cutout-mode",
        choices=("auto", "alpha-only", "opaque"),
        default="auto",
        help="auto uses embedded alpha or conservative uniform-border removal",
    )
    parser.add_argument(
        "--heuristic-rig",
        action="store_true",
        help="Force the deterministic silhouette rig instead of trying available local AI pose backends first",
    )
    parser.add_argument(
        "--joint-overrides",
        default=None,
        help="Optional krolik.rig-joint-overrides/1 JSON produced by a manual rig editor",
    )
    args = parser.parse_args()

    overrides = load_joint_overrides(args.joint_overrides) if args.joint_overrides else None
    result = build_character_runtime_package(
        Path(args.project_root),
        Path(args.source),
        args.character_id,
        name=args.name,
        cutout_mode=args.cutout_mode,
        prefer_ai_rig=not args.heuristic_rig,
        joint_overrides=overrides,
    )

    try:
        integrity = validate_built_import(result)
    except ImportIntegrityError as exc:
        print(f"KROLIK_CHARACTER_IMPORT_INTEGRITY status=failed error={exc}")
        return 3

    try:
        runtime_integrity = seal_built_runtime_package(result)
    except RuntimePackageIntegrityError as exc:
        print(f"KROLIK_RUNTIME_PACKAGE_INTEGRITY status=failed error={exc}")
        return 4
    result["package_receipt"] = runtime_integrity["package_receipt"]

    ordered = [
        "character_id", "source_sha256", "cutout_method", "cutout_confidence",
        "review_required", "alpha_coverage", "backend", "rig_review_required", "rig_score", "runtime_ready",
        "joints", "bones", "vertices", "triangles", "bone_weights", "collision_proxies",
        "joint_override_count", "joint_changed_count", "joint_changed", "joint_max_delta",
        "original", "cutout", "receipt", "rig_edit", "manifest", "image", "package_receipt",
    ]
    print("KROLIK_CHARACTER_IMPORT " + " ".join(f"{key}={result.get(key)}" for key in ordered))
    print(
        "KROLIK_CHARACTER_IMPORT_INTEGRITY "
        f"status=ok source_sha256={integrity['source_sha256']} cutout_sha256={integrity['cutout_sha256']}"
    )
    print(
        "KROLIK_RUNTIME_PACKAGE_INTEGRITY "
        f"status=ok character_id={runtime_integrity['character_id']} "
        f"manifest_sha256={runtime_integrity['manifest_sha256']} "
        f"image_sha256={runtime_integrity['image_sha256']} "
        f"rig_edit_verified={runtime_integrity['rig_edit_verified']}"
    )
    return 0 if result.get("runtime_ready") else 2


if __name__ == "__main__":
    raise SystemExit(main())
