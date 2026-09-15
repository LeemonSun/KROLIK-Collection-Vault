from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

import character_import
from rig_tools import heuristic_rig


def _source(path: Path) -> None:
    image = Image.new("RGBA", (160, 300), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((55, 10, 105, 60), fill=(80, 80, 90, 255))
    draw.rounded_rectangle((45, 55, 115, 180), radius=16, fill=(80, 80, 90, 255))
    draw.polygon([(55, 170), (78, 170), (72, 282), (48, 288)], fill=(80, 80, 90, 255))
    draw.polygon([(82, 170), (105, 170), (112, 288), (88, 282)], fill=(80, 80, 90, 255))
    image.save(path, "PNG")


def test_ai_requested_heuristic_fallback_is_explicitly_reviewable(tmp_path: Path, monkeypatch) -> None:
    source = tmp_path / "character.png"
    _source(source)

    def forced_fallback(path, prefer_ai=True):
        assert prefer_ai is True
        return heuristic_rig(path)

    monkeypatch.setattr(character_import, "detect_rig", forced_fallback)
    result = character_import.build_character_runtime_package(
        tmp_path / "project", source, "review-me", prefer_ai_rig=True
    )

    assert result["backend"] == "heuristic-silhouette"
    assert result["rig_review_required"] is True
    assert result["runtime_ready"] is True

    manifest = json.loads(Path(result["manifest"]).read_text(encoding="utf-8"))
    assert manifest["rig"]["backend"] == "heuristic-silhouette"


def test_explicit_heuristic_choice_is_not_misreported_as_ai_failure(tmp_path: Path) -> None:
    source = tmp_path / "character.png"
    _source(source)
    result = character_import.build_character_runtime_package(
        tmp_path / "project", source, "manual-heuristic", prefer_ai_rig=False
    )
    assert result["backend"] == "heuristic-silhouette"
    assert result["rig_review_required"] is False
