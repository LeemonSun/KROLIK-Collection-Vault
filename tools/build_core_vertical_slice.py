from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

from character_import import build_character_runtime_package


CHARACTER_ID = "ci_core_slice"
WIDTH = 256
HEIGHT = 512


def build_fixture_image(path: Path) -> Path:
    """Create an ordinary opaque user-like image for integration testing.

    Unlike the previous fixture, this image has no alpha channel.  CI must pass
    through the same immutable-original + derived-cutout import path available
    to a user-supplied image before rigging/runtime export begins.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (WIDTH, HEIGHT), (246, 246, 246))
    draw = ImageDraw.Draw(image)
    ink = (45, 48, 58)

    draw.ellipse((92, 28, 164, 100), fill=ink)
    draw.rectangle((116, 88, 140, 128), fill=ink)
    draw.rounded_rectangle((78, 112, 178, 300), radius=24, fill=ink)
    draw.ellipse((76, 266, 180, 330), fill=ink)
    draw.polygon([(82, 132), (54, 150), (40, 258), (64, 266), (92, 178)], fill=ink)
    draw.polygon([(174, 132), (202, 150), (216, 258), (192, 266), (164, 178)], fill=ink)
    draw.polygon([(92, 300), (122, 300), (116, 462), (82, 486), (72, 474), (88, 452)], fill=ink)
    draw.polygon([(134, 300), (164, 300), (168, 452), (184, 474), (174, 486), (140, 462)], fill=ink)

    image.save(path, "PNG")
    return path


def build_core_vertical_slice(output_root: Path) -> dict[str, object]:
    output_root = output_root.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    fixture = build_fixture_image(output_root / "fixture_input.png")

    metrics = build_character_runtime_package(
        output_root,
        fixture,
        CHARACTER_ID,
        name="CI Core Vertical Slice",
        cutout_mode="auto",
        prefer_ai_rig=False,
        cell_id="ci-room",
    )

    if metrics["cutout_method"] != "uniform-border-v1":
        raise RuntimeError(f"ordinary image did not traverse auto-cutout path: {metrics}")
    if metrics["review_required"]:
        raise RuntimeError(f"deterministic plain-background cutout unexpectedly needs review: {metrics}")
    if metrics["backend"] != "heuristic-silhouette":
        raise RuntimeError(f"unexpected deterministic rig backend: {metrics['backend']}")
    if not metrics["runtime_ready"] or float(metrics["rig_score"] or 0.0) < 99.0:
        raise RuntimeError(f"vertical slice rig not runtime-ready: {metrics}")
    if metrics["joints"] != 15 or metrics["bones"] < 14:
        raise RuntimeError(f"vertical slice rig incomplete: {metrics}")
    if metrics["vertices"] <= 0 or metrics["triangles"] <= 0 or metrics["bone_weights"] <= 0:
        raise RuntimeError(f"vertical slice skin recipe incomplete: {metrics}")
    if metrics["collision_proxies"] <= 0:
        raise RuntimeError(f"vertical slice collision proxies missing: {metrics}")

    return metrics


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a deterministic KROLIK real-image core vertical slice")
    parser.add_argument("--output-root", default="runtime_godot/.ci_vertical_slice")
    args = parser.parse_args()
    metrics = build_core_vertical_slice(Path(args.output_root))
    ordered = [
        "character_id", "source_sha256", "cutout_method", "cutout_confidence", "review_required",
        "alpha_coverage", "backend", "rig_score", "runtime_ready", "joints", "bones", "vertices",
        "triangles", "bone_weights", "collision_proxies", "original", "cutout", "receipt", "manifest", "image",
    ]
    print("KROLIK_CORE_VERTICAL_SLICE " + " ".join(f"{key}={metrics.get(key)}" for key in ordered))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
