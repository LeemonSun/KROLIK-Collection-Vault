from __future__ import annotations

"""Measure KROLIK's real DWPose path on a tiny COCO ground-truth fixture.

The input JSON is ordinary COCO keypoint format.  For each selected person we
retain the full RGB image but build a temporary alpha mask over the annotated
person bbox.  That mirrors KROLIK's single-character cutout contract: DWPose
uses the cutout bbox rather than a separate detector, while affine sampling can
still see surrounding RGB context.
"""

import argparse
import json
from pathlib import Path
import tempfile

from PIL import Image, ImageDraw

from dwpose_benchmark import DWPoseBenchmarkError, score_coco_body_joints, summarize_benchmark
from rig_tools import _dwpose_infer_points, _dwpose_keypoints_to_rig


def _bbox_alpha_fixture(source: Path, bbox: list[float], destination: Path) -> tuple[int, int]:
    with Image.open(source) as opened:
        image = opened.convert("RGBA")
    width, height = image.size
    x, y, bw, bh = [float(value) for value in bbox]
    left = max(0, min(width - 1, int(round(x))))
    top = max(0, min(height - 1, int(round(y))))
    right = max(left + 1, min(width, int(round(x + bw))))
    bottom = max(top + 1, min(height, int(round(y + bh))))
    alpha = Image.new("L", (width, height), 0)
    ImageDraw.Draw(alpha).rectangle((left, top, right - 1, bottom - 1), fill=255)
    image.putalpha(alpha)
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, "PNG")
    return width, height


def _load_document(path: Path) -> dict:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise DWPoseBenchmarkError(f"unable to read COCO annotation JSON: {exc}") from exc
    if not isinstance(document, dict):
        raise DWPoseBenchmarkError("COCO annotation root must be an object")
    if not isinstance(document.get("images"), list) or not isinstance(document.get("annotations"), list):
        raise DWPoseBenchmarkError("COCO annotation JSON must contain images and annotations arrays")
    return document


def run_benchmark(
    annotation_json: str | Path,
    image_dir: str | Path,
    *,
    max_samples: int = 8,
    min_keypoints: int = 12,
    visible_only: bool = False,
) -> tuple[dict, list[dict]]:
    annotation_path = Path(annotation_json).resolve()
    images_root = Path(image_dir).resolve()
    document = _load_document(annotation_path)
    images = {int(item["id"]): item for item in document["images"] if isinstance(item, dict) and "id" in item}

    candidates = []
    for annotation in document["annotations"]:
        if not isinstance(annotation, dict):
            continue
        if int(annotation.get("category_id", 1)) != 1 or int(annotation.get("iscrowd", 0)) != 0:
            continue
        if int(annotation.get("num_keypoints", 0)) < int(min_keypoints):
            continue
        image_id = int(annotation.get("image_id", -1))
        image_info = images.get(image_id)
        if not image_info:
            continue
        bbox = annotation.get("bbox")
        keypoints = annotation.get("keypoints")
        if not isinstance(bbox, list) or len(bbox) != 4 or not isinstance(keypoints, list):
            continue
        candidates.append((annotation, image_info))
    if not candidates:
        raise DWPoseBenchmarkError("COCO fixture has no eligible person annotations")

    candidates.sort(key=lambda pair: int(pair[0].get("id", 0)))
    selected = candidates[: max(1, int(max_samples))]
    sample_errors: list[list[float]] = []
    confidences: list[float] = []
    details: list[dict] = []

    with tempfile.TemporaryDirectory(prefix="krolik-dwpose-coco-") as temp_dir:
        temp_root = Path(temp_dir)
        for annotation, image_info in selected:
            filename = str(image_info.get("file_name") or "")
            source = images_root / filename
            if not source.is_file():
                raise DWPoseBenchmarkError(f"COCO image missing: {source}")
            fixture = temp_root / f"{int(annotation.get('id', 0))}.png"
            _bbox_alpha_fixture(source, annotation["bbox"], fixture)

            inference = _dwpose_infer_points(fixture)
            if inference is None:
                raise DWPoseBenchmarkError(f"DWPose inference failed for annotation {annotation.get('id')}")
            points, scores, diagnostics = inference
            mapped = _dwpose_keypoints_to_rig(
                points,
                scores,
                int(diagnostics["source_size"][0]),
                int(diagnostics["source_size"][1]),
            )
            if mapped is None:
                raise DWPoseBenchmarkError(
                    f"KROLIK production confidence gate rejected annotation {annotation.get('id')}; "
                    f"core_scores={diagnostics.get('core_scores')}"
                )

            errors = score_coco_body_joints(
                points,
                annotation["keypoints"],
                annotation["bbox"],
                visible_only=visible_only,
            )
            sample_errors.append(errors)
            confidence = float(mapped.settings.get("pose_confidence", 0.0))
            confidences.append(confidence)
            details.append({
                "annotation_id": int(annotation.get("id", 0)),
                "image_id": int(annotation.get("image_id", 0)),
                "file_name": filename,
                "scored_joints": len(errors),
                "mean_error": round(sum(errors) / len(errors), 6),
                "max_error": round(max(errors), 6),
                "pose_confidence": round(confidence, 6),
                "core_above_018": int(diagnostics.get("core_above_018", 0)),
            })

    summary = summarize_benchmark(sample_errors, confidences).as_dict()
    return summary, details


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark KROLIK DWPose against COCO human keypoints")
    parser.add_argument("annotation_json")
    parser.add_argument("image_dir")
    parser.add_argument("--max-samples", type=int, default=8)
    parser.add_argument("--min-keypoints", type=int, default=12)
    parser.add_argument("--visible-only", action="store_true")
    parser.add_argument("--max-mean-error", type=float, default=None)
    parser.add_argument("--min-pck-10", type=float, default=None)
    args = parser.parse_args()

    try:
        summary, details = run_benchmark(
            args.annotation_json,
            args.image_dir,
            max_samples=args.max_samples,
            min_keypoints=args.min_keypoints,
            visible_only=args.visible_only,
        )
    except Exception as exc:
        print(f"KROLIK_DWPOSE_COCO status=failed error={exc}")
        return 2

    print("KROLIK_DWPOSE_COCO_SAMPLES " + json.dumps(details, sort_keys=True, separators=(",", ":")))
    print(
        "KROLIK_DWPOSE_COCO status=ok "
        f"samples={summary['samples']} joints={summary['joints']} "
        f"mean_error={summary['mean_error']:.6f} median_error={summary['median_error']:.6f} "
        f"pck_05={summary['pck_05']:.6f} pck_10={summary['pck_10']:.6f} "
        f"mean_pose_confidence={summary['mean_pose_confidence']:.6f}"
    )
    if args.max_mean_error is not None and float(summary["mean_error"]) > args.max_mean_error:
        print(
            "KROLIK_DWPOSE_COCO_GATE status=failed "
            f"mean_error={summary['mean_error']:.6f} max={args.max_mean_error:.6f}"
        )
        return 3
    if args.min_pck_10 is not None and float(summary["pck_10"]) < args.min_pck_10:
        print(
            "KROLIK_DWPOSE_COCO_GATE status=failed "
            f"pck_10={summary['pck_10']:.6f} min={args.min_pck_10:.6f}"
        )
        return 4
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
