from __future__ import annotations

import json
from pathlib import Path

import pytest

from rig_edit import (
    RIG_EDIT_SCHEMA,
    apply_joint_overrides,
    build_joint_override_document,
    load_joint_overrides,
)


BASE = {
    "head": {"x": 0.5, "y": 0.1},
    "neck": {"x": 0.5, "y": 0.2},
    "left_wrist": {"x": 0.25, "y": 0.52},
}


def test_joint_override_document_roundtrips_and_preserves_source() -> None:
    original = {name: dict(point) for name, point in BASE.items()}
    document = build_joint_override_document({"left_wrist": {"x": 0.19, "y": 0.49}})
    assert document["schema"] == RIG_EDIT_SCHEMA

    edited, report = apply_joint_overrides(original, document)
    assert original == BASE
    assert edited["left_wrist"] == {"x": 0.19, "y": 0.49}
    assert edited["head"] == BASE["head"]
    assert report["override_count"] == 1
    assert report["changed_count"] == 1
    assert report["changed_joints"] == ["left_wrist"]
    assert report["max_delta"] > 0.0


def test_joint_override_file_loads_versioned_contract(tmp_path: Path) -> None:
    path = tmp_path / "edit.json"
    path.write_text(json.dumps({
        "schema": RIG_EDIT_SCHEMA,
        "format_version": 1,
        "joints": {"head": {"x": 0.51, "y": 0.09}},
    }), encoding="utf-8")
    assert load_joint_overrides(path) == {"head": {"x": 0.51, "y": 0.09}}


@pytest.mark.parametrize(
    "document",
    [
        {"unknown": {"x": 0.5, "y": 0.5}},
        {"head": {"x": -0.1, "y": 0.5}},
        {"head": {"x": 0.5, "y": 1.1}},
        {"head": {"x": "nan", "y": 0.5}},
        {"head": {"x": 0.5}},
        {"schema": "krolik.rig-joint-overrides/999", "joints": {}},
    ],
)
def test_invalid_joint_overrides_are_rejected(document) -> None:
    with pytest.raises(ValueError):
        apply_joint_overrides(BASE, document)


def test_cannot_override_joint_missing_from_detected_rig() -> None:
    with pytest.raises(ValueError, match="missing rig joint"):
        apply_joint_overrides({"head": BASE["head"]}, {"left_wrist": {"x": 0.2, "y": 0.5}})
