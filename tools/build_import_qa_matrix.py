from __future__ import annotations

"""Build a deterministic multi-format import matrix for end-to-end QA.

The matrix intentionally stays synthetic/deterministic so CI is reproducible,
but unlike the single vertical-slice fixture it covers multiple file formats,
alpha conditions and body/image proportions through the production import API.
"""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

from character_import import build_character_runtime_package


def _humanoid(draw: ImageDraw.ImageDraw, width: int, height: int, ink, *, compact: bool = False) -> None:
    cx = width // 2
    head_w = max(28, int(width * (0.20 if not compact else 0.18)))
    head_h = max(28, int(height * 0.14))
    top = int(height * 0.055)
    draw.ellipse((cx - head_w // 2, top, cx + head_w // 2, top + head_h), fill=ink)

    neck_w = max(10, int(width * 0.08))
    neck_top = top + int(head_h * 0.82)
    neck_bottom = int(height * 0.25)
    draw.rectangle((cx - neck_w // 2, neck_top, cx + neck_w // 2, neck_bottom), fill=ink)

    torso_half = int(width * (0.17 if not compact else 0.15))
    torso_top = int(height * 0.20)
    torso_bottom = int(height * 0.61)
    draw.rounded_rectangle(
        (cx - torso_half, torso_top, cx + torso_half, torso_bottom),
        radius=max(10, int(width * 0.06)),
        fill=ink,
    )
    draw.ellipse(
        (cx - int(width * 0.18), int(height * 0.54), cx + int(width * 0.18), int(height * 0.68)),
        fill=ink,
    )

    shoulder_y = int(height * 0.25)
    elbow_y = int(height * 0.43)
    wrist_y = int(height * 0.57)
    arm_outer = int(width * (0.28 if not compact else 0.25))
    arm_inner = int(width * 0.13)
    arm_thick = max(9, int(width * 0.045))
    draw.polygon(
        [(cx - arm_inner, shoulder_y), (cx - arm_outer, int(height * 0.30)),
         (cx - arm_outer - arm_thick, wrist_y), (cx - arm_outer + arm_thick, wrist_y),
         (cx - int(width * 0.10), elbow_y)], fill=ink
    )
    draw.polygon(
        [(cx + arm_inner, shoulder_y), (cx + arm_outer, int(height * 0.30)),
         (cx + arm_outer + arm_thick, wrist_y), (cx + arm_outer - arm_thick, wrist_y),
         (cx + int(width * 0.10), elbow_y)], fill=ink
    )

    pelvis_y = int(height * 0.61)
    ankle_y = int(height * 0.93)
    hip_dx = int(width * 0.10)
    leg_dx = int(width * 0.08)
    leg_half = max(9, int(width * 0.045))
    for side in (-1, 1):
        hip_x = cx + side * hip_dx
        ankle_x = cx + side * leg_dx
        draw.polygon(
            [(hip_x - leg_half, pelvis_y), (hip_x + leg_half, pelvis_y),
             (ankle_x + leg_half, ankle_y), (ankle_x + side * int(width * 0.06), int(height * 0.965)),
             (ankle_x - side * int(width * 0.02), int(height * 0.975)), (ankle_x - leg_half, ankle_y)],
            fill=ink,
        )


def _fixture_alpha_png(path: Path) -> tuple[int, int]:
    width, height = 224, 448
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    _humanoid(ImageDraw.Draw(image), width, height, (64, 58, 76, 255))
    image.save(path, "PNG")
    return width, height


def _fixture_opaque_png(path: Path) -> tuple[int, int]:
    width, height = 256, 512
    image = Image.new("RGB", (width, height), (246, 246, 246))
    _humanoid(ImageDraw.Draw(image), width, height, (45, 48, 58))
    image.save(path, "PNG")
    return width, height


def _fixture_jpeg(path: Path) -> tuple[int, int]:
    width, height = 240, 480
    image = Image.new("RGB", (width, height), (238, 235, 230))
    _humanoid(ImageDraw.Draw(image), width, height, (52, 60, 68))
    image.save(path, "JPEG", quality=92, subsampling=0)
    return width, height


def _fixture_compact_png(path: Path) -> tuple[int, int]:
    width, height = 320, 384
    image = Image.new("RGB", (width, height), (232, 238, 242))
    _humanoid(ImageDraw.Draw(image), width, height, (50, 47, 62), compact=True)
    image.save(path, "PNG")
    return width, height


FIXTURES = (
    ("qa-alpha-png", "alpha.png", _fixture_alpha_png, "embedded-alpha"),
    ("qa-opaque-png", "opaque.png", _fixture_opaque_png, "uniform-border-v1"),
    ("qa-jpeg", "ordinary.jpg", _fixture_jpeg, "uniform-border-v1"),
    ("qa-compact-png", "compact.png", _fixture_compact_png, "uniform-border-v1"),
)


def build_import_qa_matrix(output_root: Path) -> dict[str, object]:
    root = output_root.resolve()
    fixture_root = root / "fixtures"
    fixture_root.mkdir(parents=True, exist_ok=True)
    entries: list[dict[str, object]] = []

    for character_id, filename, builder, expected_cutout in FIXTURES:
        source = fixture_root / filename
        expected_width, expected_height = builder(source)
        result = build_character_runtime_package(
            root,
            source,
            character_id,
            name=character_id,
            cutout_mode="auto",
            prefer_ai_rig=False,
            cell_id="qa-room",
        )
        if result["cutout_method"] != expected_cutout:
            raise RuntimeError(f"{character_id}: cutout method {result['cutout_method']} != {expected_cutout}")
        if result["review_required"]:
            raise RuntimeError(f"{character_id}: deterministic fixture unexpectedly requires cutout review")
        if result["backend"] != "heuristic-silhouette":
            raise RuntimeError(f"{character_id}: unexpected rig backend {result['backend']}")
        if not result["runtime_ready"] or float(result["rig_score"]) < 99.0:
            raise RuntimeError(f"{character_id}: runtime package is not ready")
        if result["joints"] != 15 or result["bones"] != 14 or result["bone_weights"] != 14:
            raise RuntimeError(f"{character_id}: rig/skin contract is incomplete")
        if result["collision_proxies"] != 14:
            raise RuntimeError(f"{character_id}: collision proxy contract is incomplete")
        if int(result["width"]) != expected_width or int(result["height"]) != expected_height:
            raise RuntimeError(f"{character_id}: normalized dimensions changed unexpectedly")

        manifest_path = Path(str(result["manifest"])).resolve()
        try:
            manifest_rel = manifest_path.relative_to(root).as_posix()
        except ValueError as exc:
            raise RuntimeError(f"{character_id}: manifest escaped matrix root") from exc
        entries.append({
            "character_id": character_id,
            "source_name": filename,
            "source_sha256": result["source_sha256"],
            "manifest": manifest_rel,
            "width": expected_width,
            "height": expected_height,
            "cutout_method": result["cutout_method"],
            "cutout_confidence": result["cutout_confidence"],
            "alpha_coverage": result["alpha_coverage"],
            "rig_score": result["rig_score"],
            "vertices": result["vertices"],
            "triangles": result["triangles"],
        })

    matrix = {
        "schema": "krolik.import-qa-matrix/1",
        "count": len(entries),
        "entries": entries,
    }
    matrix_path = root / "matrix.json"
    matrix_path.write_text(json.dumps(matrix, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"matrix": str(matrix_path), "count": len(entries), "entries": entries}


def main() -> int:
    parser = argparse.ArgumentParser(description="Build KROLIK multi-format character import QA matrix")
    parser.add_argument("--output-root", default="runtime_godot/.ci_import_matrix")
    args = parser.parse_args()
    result = build_import_qa_matrix(Path(args.output_root))
    methods = ",".join(str(entry["cutout_method"]) for entry in result["entries"])
    print(f"KROLIK_IMPORT_QA_MATRIX count={result['count']} methods={methods} matrix={result['matrix']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
