from __future__ import annotations

import argparse
from pathlib import Path

from character_import import build_character_runtime_package


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
    args = parser.parse_args()

    result = build_character_runtime_package(
        Path(args.project_root),
        Path(args.source),
        args.character_id,
        name=args.name,
        cutout_mode=args.cutout_mode,
        prefer_ai_rig=not args.heuristic_rig,
    )

    ordered = [
        "character_id",
        "source_sha256",
        "cutout_method",
        "cutout_confidence",
        "review_required",
        "alpha_coverage",
        "backend",
        "rig_score",
        "runtime_ready",
        "joints",
        "bones",
        "vertices",
        "triangles",
        "bone_weights",
        "collision_proxies",
        "original",
        "cutout",
        "receipt",
        "manifest",
        "image",
    ]
    print("KROLIK_CHARACTER_IMPORT " + " ".join(f"{key}={result.get(key)}" for key in ordered))
    return 0 if result.get("runtime_ready") else 2


if __name__ == "__main__":
    raise SystemExit(main())
