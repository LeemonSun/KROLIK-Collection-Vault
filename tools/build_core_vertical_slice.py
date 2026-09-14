from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

from rig_tools import detect_rig
from runtime_package import build_manifest, write_package


CHARACTER_ID = "ci_core_slice"
WIDTH = 256
HEIGHT = 512


def build_fixture_image(path: Path) -> Path:
    """Create a deterministic transparent humanoid input for integration testing.

    This is deliberately a test fixture, not generated concept art and not a
    replacement for the real user-import path. It exists so CI can exercise the
    actual image->rig->skin->manifest->Godot contract without network/models.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    ink = (235, 235, 235, 255)

    # Head / neck.
    draw.ellipse((92, 28, 164, 100), fill=ink)
    draw.rectangle((116, 88, 140, 128), fill=ink)

    # Torso / pelvis.
    draw.rounded_rectangle((78, 112, 178, 300), radius=24, fill=ink)
    draw.ellipse((76, 266, 180, 330), fill=ink)

    # Arms with enough silhouette width for the heuristic row probes.
    draw.polygon([(82, 132), (54, 150), (40, 258), (64, 266), (92, 178)], fill=ink)
    draw.polygon([(174, 132), (202, 150), (216, 258), (192, 266), (164, 178)], fill=ink)

    # Legs / feet.
    draw.polygon([(92, 300), (122, 300), (116, 462), (82, 486), (72, 474), (88, 452)], fill=ink)
    draw.polygon([(134, 300), (164, 300), (168, 452), (184, 474), (174, 486), (140, 462)], fill=ink)

    image.save(path, "PNG")
    return path


def build_core_vertical_slice(output_root: Path) -> dict[str, object]:
    output_root = output_root.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    fixture = build_fixture_image(output_root / "fixture_input.png")

    detection = detect_rig(fixture, prefer_ai=False)
    settings = dict(detection.settings)
    joints = detection.joints

    character = {
        "id": CHARACTER_ID,
        "name": "CI Core Vertical Slice",
        "status": "test-fixture",
    }
    image_version = {
        "id": 1,
        "width": WIDTH,
        "height": HEIGHT,
        "kind": "derived-cutout-fixture",
    }
    rig = {
        "id": 1,
        "rest_json": json.dumps({"joints": joints}, ensure_ascii=False),
        "settings_json": json.dumps(settings, ensure_ascii=False),
    }
    mind = {
        "enabled": 1,
        "state": "idle",
        "home_cell_id": "ci-room",
        "profile_json": json.dumps(
            {
                "mobility": "auto",
                "routine": "explorer",
                "autonomy": 0.90,
                "wander": 0.90,
                "social": 0.20,
                "rest_threshold": 0.20,
                "curiosity_threshold": 0.60,
                "home_bias": 0.25,
                "walk_speed": 1.0,
            }
        ),
        "needs_json": json.dumps(
            {"energy": 0.95, "comfort": 0.80, "curiosity": 0.65, "social": 0.20}
        ),
        "runtime_json": "{}",
    }

    manifest = build_manifest(
        character=character,
        image_version=image_version,
        rig=rig,
        mind=mind,
        cell_id="ci-room",
    )
    package = write_package(output_root, CHARACTER_ID, fixture, manifest)

    manifest_path = Path(str(package["manifest"]))
    written = json.loads(manifest_path.read_text(encoding="utf-8"))
    skin = written.get("rig", {}).get("skinning", {})
    metrics = {
        "character_id": CHARACTER_ID,
        "backend": written.get("rig", {}).get("backend"),
        "rig_score": written.get("quality", {}).get("rig_score"),
        "runtime_ready": written.get("quality", {}).get("runtime_ready"),
        "joints": len(written.get("rig", {}).get("joints", {})),
        "bones": len(written.get("rig", {}).get("bones", [])),
        "vertices": len(skin.get("vertices", [])),
        "triangles": len(skin.get("triangles", [])) // 3,
        "bone_weights": len(skin.get("bone_weights", [])),
        "collision_proxies": len(written.get("physics", {}).get("collision", [])),
        "manifest": str(manifest_path),
        "image": str(package["image"]),
    }

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
    parser = argparse.ArgumentParser(description="Build a deterministic KROLIK core vertical-slice runtime package")
    parser.add_argument("--output-root", default="runtime_godot/.ci_vertical_slice")
    args = parser.parse_args()
    metrics = build_core_vertical_slice(Path(args.output_root))
    print("KROLIK_CORE_VERTICAL_SLICE " + " ".join(f"{key}={value}" for key, value in metrics.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
