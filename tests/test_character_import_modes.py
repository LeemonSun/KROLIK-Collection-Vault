from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

from character_import import prepare_character_asset


def test_same_source_different_cutout_modes_do_not_collide(tmp_path: Path) -> None:
    source = tmp_path / "source.png"
    image = Image.new("RGB", (128, 192), (245, 245, 245))
    ImageDraw.Draw(image).rounded_rectangle((38, 14, 90, 180), radius=18, fill=(40, 45, 55))
    image.save(source, "PNG")

    project = tmp_path / "project"
    auto = prepare_character_asset(project, source, "mode-char", cutout_mode="auto")
    opaque = prepare_character_asset(project, source, "mode-char", cutout_mode="opaque")

    assert auto["source_sha256"] == opaque["source_sha256"]
    assert auto["original"] == opaque["original"]
    assert auto["cutout"] != opaque["cutout"]
    assert auto["receipt"] != opaque["receipt"]
    assert auto["cutout_method"] == "uniform-border-v1"
    assert opaque["cutout_method"] == "opaque-preserve"
    assert auto["cutout_sha256"] != opaque["cutout_sha256"]

    auto_receipt = json.loads(Path(auto["receipt"]).read_text(encoding="utf-8"))
    opaque_receipt = json.loads(Path(opaque["receipt"]).read_text(encoding="utf-8"))
    assert auto_receipt["derived"]["requested_mode"] == "auto"
    assert opaque_receipt["derived"]["requested_mode"] == "opaque"
