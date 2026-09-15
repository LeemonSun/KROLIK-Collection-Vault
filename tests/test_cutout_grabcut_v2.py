from __future__ import annotations

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
