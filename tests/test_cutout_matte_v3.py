from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import character_import
from cutout_matte import decontaminate_alpha_edges, measure_edge_halo


def _halo_fixture() -> Image.Image:
    h = w = 96
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[:, :, :3] = 255
    subject = np.array([36, 31, 42], dtype=np.float32)
    for inset, alpha in [(20, 64), (21, 112), (22, 176), (23, 224)]:
        a = alpha / 255.0
        observed = np.clip(subject * a + 255.0 * (1.0 - a), 0, 255).astype(np.uint8)
        rgba[inset:h-inset, inset:w-inset, :3] = observed
        rgba[inset:h-inset, inset:w-inset, 3] = alpha
    rgba[24:72, 24:72, :3] = subject.astype(np.uint8)
    rgba[24:72, 24:72, 3] = 255
    return Image.fromarray(rgba, mode='RGBA')


def test_matte_v3_preserves_alpha_and_removes_edge_halo() -> None:
    source = _halo_fixture()
    before_alpha = np.asarray(source.getchannel('A'), dtype=np.uint8).copy()
    before = measure_edge_halo(source)['halo_score']
    cleaned, metrics = decontaminate_alpha_edges(source)
    after_alpha = np.asarray(cleaned.getchannel('A'), dtype=np.uint8)
    after = measure_edge_halo(cleaned)['halo_score']
    assert np.array_equal(before_alpha, after_alpha)
    assert metrics['edge_cleanup_applied'] is True
    assert metrics['transparent_padding_pixels'] > 0
    assert after < before * 0.45
    assert metrics['matte_quality'] > 0.35


def test_character_import_v3_records_matte_quality(tmp_path: Path) -> None:
    image = Image.new('RGB', (256, 384), (232, 24, 156))
    draw = ImageDraw.Draw(image)
    draw.ellipse((86, 24, 170, 112), fill=(28, 24, 32))
    draw.rectangle((72, 96, 184, 346), fill=(34, 28, 38))
    source = tmp_path / 'card.png'
    image.save(source)
    result = character_import.prepare_character_asset(tmp_path / 'project', source, 'matte-v3')
    assert character_import.CUTOUT_ALGORITHM_VERSION == 3
    assert '/v3/' in result['cutout'].replace('\\', '/')
    assert result['matte_quality_version'] == 3
    assert 0.0 <= result['edge_halo_score_after'] <= 1.0
    assert 0.0 <= result['matte_quality'] <= 1.0
