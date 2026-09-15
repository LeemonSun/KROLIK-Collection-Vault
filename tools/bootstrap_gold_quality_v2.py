from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"bootstrap marker missing: {label}")
    return text.replace(old, new, 1)


character_path = ROOT / "character_import.py"
character = character_path.read_text(encoding="utf-8")
character = replace_once(
    character,
    "import numpy as np\nfrom PIL import Image, ImageOps\n",
    "import numpy as np\nfrom PIL import Image, ImageOps\n\ntry:\n    import cv2  # type: ignore\nexcept Exception:  # pragma: no cover\n    cv2 = None  # type: ignore\n",
    "opencv-import",
)
character = replace_once(character, "CUTOUT_ALGORITHM_VERSION = 1", "CUTOUT_ALGORITHM_VERSION = 2", "cutout-version")

cutout_insert = r'''
def _largest_component(mask: np.ndarray) -> tuple[np.ndarray, float]:
    """Keep the dominant connected foreground component and report its dominance."""
    if cv2 is None:
        return mask, 1.0
    binary = (mask > 0).astype(np.uint8)
    count, labels, stats, _centroids = cv2.connectedComponentsWithStats(binary, 8)
    if count <= 1:
        return mask, 1.0
    areas = [int(stats[index, cv2.CC_STAT_AREA]) for index in range(1, count)]
    if not areas:
        return np.zeros_like(mask), 0.0
    best_offset = int(np.argmax(np.asarray(areas)))
    best_index = best_offset + 1
    total = max(1, sum(areas))
    kept = np.where(labels == best_index, 255, 0).astype(np.uint8)
    return kept, float(areas[best_offset]) / float(total)


def _center_grabcut_refine(
    image: Image.Image,
    prior: Image.Image,
) -> tuple[Image.Image, dict[str, Any]] | None:
    """Refine a weak border cutout for centered single-character artwork.

    This is deliberately a fallback, not the first choice. GrabCut gets a
    conservative central rectangle, then the dominant component is retained.
    A narrow band of the previous alpha is allowed back around that component
    so fine hair/cloth edges survive without re-introducing a studio floor.
    """
    if cv2 is None:
        return None
    rgb = np.asarray(image.convert("RGB"), dtype=np.uint8)
    height, width = rgb.shape[:2]
    if width < 48 or height < 64:
        return None

    margin_x = max(2, int(round(width * 0.04)))
    margin_top = max(2, int(round(height * 0.015)))
    margin_bottom = max(2, int(round(height * 0.018)))
    rect_width = width - margin_x * 2
    rect_height = height - margin_top - margin_bottom
    if rect_width < 16 or rect_height < 24:
        return None

    bgr = rgb[:, :, ::-1].copy()
    labels = np.zeros((height, width), dtype=np.uint8)
    bg_model = np.zeros((1, 65), dtype=np.float64)
    fg_model = np.zeros((1, 65), dtype=np.float64)
    try:
        cv2.grabCut(
            bgr,
            labels,
            (margin_x, margin_top, rect_width, rect_height),
            bg_model,
            fg_model,
            5,
            cv2.GC_INIT_WITH_RECT,
        )
    except Exception:
        return None

    foreground = np.where(
        (labels == cv2.GC_FGD) | (labels == cv2.GC_PR_FGD),
        255,
        0,
    ).astype(np.uint8)
    foreground, component_dominance = _largest_component(foreground)
    core_share = float(np.mean(foreground > 16))
    if not (0.025 <= core_share <= 0.88) or component_dominance < 0.72:
        return None

    ys, xs = np.where(foreground > 16)
    if not len(xs):
        return None
    bbox_height_share = float(ys.max() - ys.min() + 1) / float(height)
    bbox_width_share = float(xs.max() - xs.min() + 1) / float(width)
    if bbox_height_share < 0.35 or bbox_width_share < 0.08:
        return None

    prior_alpha = np.asarray(prior.getchannel("A"), dtype=np.uint8)
    rescue_radius = max(2, int(round(min(width, height) * 0.012)))
    kernel = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE,
        (rescue_radius * 2 + 1, rescue_radius * 2 + 1),
    )
    near_subject = cv2.dilate((foreground > 0).astype(np.uint8), kernel) > 0
    alpha = np.where(
        foreground > 0,
        np.maximum(foreground, prior_alpha),
        np.where(near_subject, prior_alpha, 0),
    ).astype(np.uint8)

    edge_band = np.zeros((height, width), dtype=bool)
    edge = max(1, int(round(min(width, height) * 0.008)))
    edge_band[:edge, :] = True
    edge_band[-edge:, :] = True
    edge_band[:, :edge] = True
    edge_band[:, -edge:] = True
    border_foreground_share = float(np.mean((alpha > 16)[edge_band]))
    foreground_share = float(np.mean(alpha > 16))
    if border_foreground_share > 0.20 or not (0.025 <= foreground_share <= 0.90):
        return None

    rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8).copy()
    rgba[:, :, 3] = alpha
    result = Image.fromarray(rgba, mode="RGBA")
    shape_quality = min(1.0, bbox_height_share / 0.72)
    confidence = round(
        max(0.0, min(0.96,
            0.68
            + 0.16 * component_dominance
            + 0.10 * shape_quality
            + 0.08 * (1.0 - min(1.0, border_foreground_share / 0.20))
        )),
        4,
    )
    return result, {
        "method": "center-grabcut-v2",
        "confidence": confidence,
        "review_required": bool(confidence < 0.76),
        "foreground_share": round(foreground_share, 6),
        "component_dominance": round(component_dominance, 6),
        "bbox_width_share": round(bbox_width_share, 6),
        "bbox_height_share": round(bbox_height_share, 6),
        "border_foreground_share": round(border_foreground_share, 6),
        "warnings": ["grabcut_centered_single_character_fallback"],
    }


'''
character = replace_once(
    character,
    "def _prepare_cutout(image: Image.Image, mode: str) -> tuple[Image.Image, dict[str, Any]]:\n",
    cutout_insert + "def _prepare_cutout(image: Image.Image, mode: str) -> tuple[Image.Image, dict[str, Any]]:\n",
    "cutout-refiner",
)
character = replace_once(
    character,
    '    if normalized_mode == "auto":\n        return _uniform_border_cutout(image)\n',
    '    if normalized_mode == "auto":\n        initial, initial_info = _uniform_border_cutout(image)\n        if not bool(initial_info.get("review_required")):\n            return initial, initial_info\n        refined = _center_grabcut_refine(image, initial)\n        if refined is not None:\n            refined_image, refined_info = refined\n            if float(refined_info.get("confidence", 0.0)) > float(initial_info.get("confidence", 0.0)):\n                return refined_image, refined_info\n        return initial, initial_info\n',
    "auto-selection",
)
character_path.write_text(character, encoding="utf-8")

rig_path = ROOT / "rig_tools.py"
rig = rig_path.read_text(encoding="utf-8")
rig = replace_once(
    rig,
    '    used_scores = [float(conf[i]) for i in required if float(conf[i]) >= 0.0]\n    quality = sum(used_scores) / max(1, len(used_scores))\n    return RigDetection(joints=joints, settings={\n',
    '''    used_scores = [float(conf[i]) for i in required if float(conf[i]) >= 0.0]\n    quality = sum(used_scores) / max(1, len(used_scores))\n\n    def conf_value(index: int) -> float:\n        return round(max(0.0, min(1.0, float(conf[index]))), 6)\n\n    face_score = (\n        sum(float(conf[index]) for index in face_candidates) / len(face_candidates)\n        if face_candidates else min(float(conf[5]), float(conf[6])) * 0.5\n    )\n    joint_confidence = {\n        "head": round(max(0.0, min(1.0, face_score)), 6),\n        "neck": round(max(0.0, min(1.0, min(float(conf[5]), float(conf[6])))), 6),\n        "left_shoulder": conf_value(5),\n        "left_elbow": conf_value(7),\n        "left_wrist": conf_value(9),\n        "right_shoulder": conf_value(6),\n        "right_elbow": conf_value(8),\n        "right_wrist": conf_value(10),\n        "pelvis": round(max(0.0, min(1.0, min(float(conf[11]), float(conf[12])))), 6),\n        "left_hip": conf_value(11),\n        "left_knee": conf_value(13),\n        "left_ankle": conf_value(15),\n        "right_hip": conf_value(12),\n        "right_knee": conf_value(14),\n        "right_ankle": conf_value(16),\n    }\n    return RigDetection(joints=joints, settings={\n''',
    "joint-confidence-map",
)
rig = replace_once(
    rig,
    '        "pose_confidence": round(float(quality), 5),\n    })\n',
    '        "pose_confidence": round(float(quality), 5),\n        "joint_confidence": joint_confidence,\n        "low_confidence_joints": sorted(\n            name for name, value in joint_confidence.items() if float(value) < min_conf\n        ),\n    })\n',
    "joint-confidence-settings",
)
rig = replace_once(
    rig,
    '    core_scores = [float(score[index]) for index in required if index < score.shape[0]]\n    diagnostics = {\n',
    '''    core_scores = [float(score[index]) for index in required if index < score.shape[0]]\n    coco_names = {\n        0: "nose", 1: "left_eye", 2: "right_eye", 3: "left_ear", 4: "right_ear",\n        5: "left_shoulder", 6: "right_shoulder", 7: "left_elbow", 8: "right_elbow",\n        9: "left_wrist", 10: "right_wrist", 11: "left_hip", 12: "right_hip",\n        13: "left_knee", 14: "right_knee", 15: "left_ankle", 16: "right_ankle",\n    }\n    named_scores = {\n        name: round(float(score[index]), 6)\n        for index, name in coco_names.items()\n        if index < score.shape[0]\n    }\n    diagnostics = {\n''',
    "diagnostic-named-scores",
)
rig = replace_once(
    rig,
    '        "core_above_018": sum(value >= .18 for value in core_scores),\n        "providers": list(session.get_providers()),\n',
    '        "core_above_018": sum(value >= .18 for value in core_scores),\n        "named_scores": named_scores,\n        "providers": list(session.get_providers()),\n',
    "diagnostic-output",
)
rig_path.write_text(rig, encoding="utf-8")

(ROOT / "tests" / "test_cutout_grabcut_v2.py").write_text(r'''from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest
from PIL import Image, ImageDraw

import character_import


def _studio_card(path: Path) -> None:
    w, h = 320, 480
    arr = np.zeros((h, w, 3), dtype=np.uint8)
    for y in range(h):
        v = int(92 + 26 * min(y, 360) / 360) if y < 360 else int(138 + 30 * (y - 360) / 120)
        arr[y, :, :] = (v, v + 2, v + 5)
    image = Image.fromarray(arr, mode="RGB")
    draw = ImageDraw.Draw(image)
    draw.ellipse((126, 28, 194, 98), fill=(34, 28, 36))
    draw.rectangle((116, 82, 204, 245), fill=(28, 24, 30))
    draw.ellipse((74, 190, 246, 330), fill=(214, 170, 170))
    draw.polygon([(103, 285), (147, 285), (139, 436), (106, 436)], fill=(52, 44, 50))
    draw.polygon([(173, 285), (217, 285), (214, 436), (181, 436)], fill=(52, 44, 50))
    draw.rectangle((96, 414, 142, 468), fill=(18, 18, 20))
    draw.rectangle((178, 414, 224, 468), fill=(18, 18, 20))
    image.save(path)


@pytest.mark.skipif(character_import.cv2 is None, reason="OpenCV unavailable")
def test_auto_cutout_uses_center_grabcut_when_border_model_is_weak(tmp_path: Path) -> None:
    source = tmp_path / "studio.png"
    _studio_card(source)
    result = character_import.prepare_character_asset(tmp_path / "project", source, "studio-card")
    assert result["cutout_method"] == "center-grabcut-v2"
    assert result["review_required"] is False
    assert result["cutout_confidence"] >= 0.76
    with Image.open(result["cutout"]).convert("RGBA") as cutout:
        alpha = np.asarray(cutout.getchannel("A"), dtype=np.uint8)
    assert float(np.mean(alpha > 16)) < 0.60
    assert float(np.mean((alpha > 16)[-4:, :])) < 0.25


def test_strong_simple_border_cutout_still_keeps_fast_v1_path(tmp_path: Path) -> None:
    image = Image.new("RGB", (256, 384), (240, 20, 160))
    draw = ImageDraw.Draw(image)
    draw.ellipse((88, 26, 168, 112), fill=(20, 20, 24))
    draw.rectangle((72, 96, 184, 345), fill=(26, 24, 30))
    source = tmp_path / "simple.png"
    image.save(source)
    result = character_import.prepare_character_asset(tmp_path / "project", source, "simple-card")
    assert result["cutout_method"] == "uniform-border-v1"
    assert result["review_required"] is False
''', encoding="utf-8")

(ROOT / "tests" / "test_dwpose_joint_confidence.py").write_text(r'''from __future__ import annotations

import numpy as np

from rig_tools import JOINT_ORDER, _dwpose_keypoints_to_rig


def test_dwpose_rig_persists_named_joint_confidence() -> None:
    points = np.zeros((17, 2), dtype=np.float32)
    coords = {
        0: (100, 30), 1: (94, 28), 2: (106, 28), 3: (88, 34), 4: (112, 34),
        5: (75, 90), 6: (125, 90), 7: (62, 145), 8: (138, 145),
        9: (55, 210), 10: (145, 210), 11: (82, 220), 12: (118, 220),
        13: (80, 310), 14: (120, 310), 15: (78, 390), 16: (122, 390),
    }
    for index, value in coords.items():
        points[index] = value
    scores = np.full((17,), 0.91, dtype=np.float32)
    scores[9] = 0.11
    rig = _dwpose_keypoints_to_rig(points, scores, 200, 420)
    assert rig is not None
    confidence = rig.settings["joint_confidence"]
    assert set(confidence) == set(JOINT_ORDER)
    assert confidence["left_wrist"] == 0.11
    assert confidence["right_wrist"] > 0.90
    assert "left_wrist" in rig.settings["low_confidence_joints"]
    assert "right_wrist" not in rig.settings["low_confidence_joints"]
''', encoding="utf-8")

print("KROLIK_GOLD_QUALITY_BOOTSTRAP status=ok")
