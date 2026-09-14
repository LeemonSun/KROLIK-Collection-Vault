from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from character_import import (
    ASSET_IMPORT_SCHEMA,
    build_character_runtime_package,
    prepare_character_asset,
)


def _draw_humanoid(image: Image.Image, ink) -> None:
    draw = ImageDraw.Draw(image)
    draw.ellipse((92, 28, 164, 100), fill=ink)
    draw.rectangle((116, 88, 140, 128), fill=ink)
    draw.rounded_rectangle((78, 112, 178, 300), radius=24, fill=ink)
    draw.ellipse((76, 266, 180, 330), fill=ink)
    draw.polygon([(82, 132), (54, 150), (40, 258), (64, 266), (92, 178)], fill=ink)
    draw.polygon([(174, 132), (202, 150), (216, 258), (192, 266), (164, 178)], fill=ink)
    draw.polygon([(92, 300), (122, 300), (116, 462), (82, 486), (72, 474), (88, 452)], fill=ink)
    draw.polygon([(134, 300), (164, 300), (168, 452), (184, 474), (174, 486), (140, 462)], fill=ink)


def test_embedded_alpha_import_preserves_original_bytes(tmp_path: Path) -> None:
    source = tmp_path / "alpha-source.png"
    image = Image.new("RGBA", (96, 160), (0, 0, 0, 0))
    ImageDraw.Draw(image).rounded_rectangle((28, 10, 68, 150), radius=14, fill=(80, 70, 90, 255))
    image.save(source, "PNG")
    source_bytes = source.read_bytes()

    result = prepare_character_asset(tmp_path / "project", source, "alpha-char")
    original = Path(result["original"])
    cutout = Path(result["cutout"])
    receipt = json.loads(Path(result["receipt"]).read_text(encoding="utf-8"))

    assert original.read_bytes() == source_bytes
    assert result["source_sha256"] == hashlib.sha256(source_bytes).hexdigest()
    assert result["cutout_method"] == "embedded-alpha"
    assert result["review_required"] is False
    assert 0.05 < float(result["alpha_coverage"]) < 0.8
    assert receipt["schema"] == ASSET_IMPORT_SCHEMA
    assert receipt["source"]["sha256"] == result["source_sha256"]
    assert receipt["derived"]["cutout_sha256"] == hashlib.sha256(cutout.read_bytes()).hexdigest()

    # Reimport is deterministic and reuses the immutable content-addressed source.
    again = prepare_character_asset(tmp_path / "project", source, "alpha-char")
    assert again["original"] == result["original"]
    assert again["cutout_sha256"] == result["cutout_sha256"]
    assert original.read_bytes() == source_bytes


def test_uniform_background_auto_cutout_builds_runtime_package(tmp_path: Path) -> None:
    source = tmp_path / "ordinary-user-image.png"
    image = Image.new("RGB", (256, 512), (246, 246, 246))
    _draw_humanoid(image, (45, 48, 58))
    image.save(source, "PNG")
    source_bytes = source.read_bytes()

    result = build_character_runtime_package(
        tmp_path / "project",
        source,
        "real-image-ci",
        name="Real Image CI",
        prefer_ai_rig=False,
    )

    assert Path(result["original"]).read_bytes() == source_bytes
    assert result["cutout_method"] == "uniform-border-v1"
    assert float(result["cutout_confidence"]) >= 0.95
    assert result["review_required"] is False
    assert 0.05 < float(result["alpha_coverage"]) < 0.75
    assert result["backend"] == "heuristic-silhouette"
    assert result["runtime_ready"] is True
    assert float(result["rig_score"]) == 100.0
    assert result["joints"] == 15
    assert result["bones"] == 14
    assert result["bone_weights"] == 14
    assert result["collision_proxies"] == 14

    with Image.open(result["cutout"]) as cutout:
        alpha = np.asarray(cutout.convert("RGBA").getchannel("A"), dtype=np.uint8)
        assert int(alpha[0, 0]) == 0
        assert int(alpha[170, 128]) > 240

    manifest = json.loads(Path(result["manifest"]).read_text(encoding="utf-8"))
    package_image = Path(result["image"])
    assert manifest["schema"] == "krolik.runtime-character/1"
    assert manifest["character"]["id"] == "real-image-ci"
    assert manifest["quality"]["runtime_ready"] is True
    assert manifest["visual"]["sha256"] == hashlib.sha256(package_image.read_bytes()).hexdigest()


def test_busy_background_falls_back_without_destructive_fake_cutout(tmp_path: Path) -> None:
    source = tmp_path / "busy.png"
    yy, xx = np.indices((96, 96))
    checker = ((xx + yy) % 2 * 255).astype(np.uint8)
    rgb = np.stack((checker, 255 - checker, checker), axis=2)
    Image.fromarray(rgb, mode="RGB").save(source, "PNG")

    result = prepare_character_asset(tmp_path / "project", source, "busy-char")
    assert result["cutout_method"] == "opaque-fallback-v1"
    assert result["review_required"] is True
    assert "auto_cutout_fallback_opaque" in result["warnings"]
    assert float(result["alpha_coverage"]) == 1.0


def test_import_rejects_non_image_input(tmp_path: Path) -> None:
    source = tmp_path / "not-image.txt"
    source.write_text("not an image", encoding="utf-8")
    try:
        prepare_character_asset(tmp_path / "project", source, "bad")
    except ValueError as exc:
        assert "decode image" in str(exc)
    else:
        raise AssertionError("non-image input must be rejected")
