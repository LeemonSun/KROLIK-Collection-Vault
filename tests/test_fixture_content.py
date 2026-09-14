from __future__ import annotations

from copy import deepcopy
import json

import pytest

from interaction_runtime import (
    anchor_point,
    fixture_runtime_profile,
    preset_constraints,
    runtime_interaction,
)
from prop_content import (
    FIXTURE_FORMAT_VERSION,
    FIXTURE_SCHEMA,
    FixtureCatalog,
    FixtureContentError,
    load_fixture_library,
    validate_fixture_document,
)


def _custom_document() -> dict:
    return {
        "schema": FIXTURE_SCHEMA,
        "format_version": FIXTURE_FORMAT_VERSION,
        "fixtures": {
            "custom_gate": {
                "category": "test_fixture",
                "tags": ["test", "socket"],
                "dimensions": {"w": 1.0, "h": 1.0},
                "render": {"layer": 12, "occlusion": "mixed", "z_offset": 0.0},
                "collision": {"profile": "solid", "shape": "rect"},
                "occupancy": {"capacity": 1, "exclusive": True},
                "anchors": {
                    "center": {"x": 0.0, "y": 0.0},
                    "socket": {"x": 0.25, "y": -0.25, "tags": ["limb"]},
                },
                "slots": {
                    "attachment": {"anchor": "socket", "accepts": ["rope", "chain"]},
                },
                "constraints": [
                    {
                        "joint": "left_wrist",
                        "anchor": "socket",
                        "strength": 0.8,
                        "max_stretch": 1.1,
                    }
                ],
            }
        },
    }


def test_bundled_fixture_catalog_is_versioned_and_general_purpose():
    catalog = FixtureCatalog()
    assert catalog.revision == 1
    assert {"wall_cuffs", "floor_shackles", "x_frame", "standing_cage", "barrel", "chain_anchor", "rope_anchor", "face_accessory_mount"}.issubset(catalog.kinds())
    cage = catalog.get("standing_cage")
    assert cage is not None
    assert cage["occupancy"]["capacity"] == 1
    assert cage["render"]["occlusion"] == "mixed"
    assert "door_latch" in cage["slots"]
    assert validate_fixture_document(catalog.document) == []


def test_existing_constraint_presets_are_now_data_driven():
    prop = {"id": 7, "kind": "x_frame", "x": 0.5, "y": 0.5, "w": 0.4, "h": 0.8, "rotation": 0.0}
    constraints = preset_constraints(prop)
    assert [(item["joint"], item["anchor"]) for item in constraints] == [
        ("left_wrist", "top_left"),
        ("right_wrist", "top_right"),
        ("left_ankle", "bottom_left"),
        ("right_ankle", "bottom_right"),
    ]
    assert all(item["prop_id"] == 7 for item in constraints)


def test_runtime_interaction_uses_fixture_anchor_data_for_targets():
    prop = {"id": 7, "kind": "x_frame", "x": 0.5, "y": 0.5, "w": 0.4, "h": 0.8, "rotation": 0.0}
    items = preset_constraints(prop)
    result = runtime_interaction(
        placement_interaction={"mode": "anchored"},
        constraint_doc={"items": items},
        props=[prop],
    )
    assert result["contained"] is True
    assert result["constraint_count"] == 4
    targets = {item["joint"]: item["target"] for item in result["constraints"]}
    assert targets["left_wrist"] == pytest.approx({"x": 0.3, "y": 0.1})
    assert targets["right_wrist"] == pytest.approx({"x": 0.7, "y": 0.1})
    assert targets["left_ankle"] == pytest.approx({"x": 0.3, "y": 0.9})
    assert targets["right_ankle"] == pytest.approx({"x": 0.7, "y": 0.9})


def test_custom_fixture_json_drives_runtime_without_code_change(tmp_path):
    path = tmp_path / "fixtures.json"
    path.write_text(json.dumps(_custom_document()), encoding="utf-8")
    catalog = FixtureCatalog(path)
    prop = {"id": 11, "kind": "custom_gate", "x": 0.5, "y": 0.5, "w": 0.4, "h": 0.8, "rotation": 0.0}

    constraints = preset_constraints(prop, catalog=catalog)
    assert len(constraints) == 1
    assert constraints[0]["joint"] == "left_wrist"
    assert constraints[0]["strength"] == pytest.approx(0.8)
    assert constraints[0]["max_stretch"] == pytest.approx(1.1)

    result = runtime_interaction(
        placement_interaction={"mode": "free"},
        constraint_doc={"items": constraints},
        props=[prop],
        catalog=catalog,
    )
    assert result["contained"] is True
    assert result["constraints"][0]["target"] == pytest.approx({"x": 0.6, "y": 0.3})
    assert anchor_point(prop, "socket", catalog=catalog) == pytest.approx({"x": 0.6, "y": 0.3})

    profile = fixture_runtime_profile(prop, catalog=catalog)
    assert profile["collision"]["profile"] == "solid"
    assert profile["occupancy"]["exclusive"] is True
    assert profile["slots"]["attachment"]["anchor"] == "socket"


def test_fixture_catalog_reload_is_explicit_and_non_destructive(tmp_path):
    path = tmp_path / "fixtures.json"
    first = _custom_document()
    path.write_text(json.dumps(first), encoding="utf-8")
    catalog = FixtureCatalog(path)
    revision = catalog.revision
    assert catalog.get("second_fixture") is None

    second = deepcopy(first)
    second["fixtures"]["second_fixture"] = deepcopy(second["fixtures"]["custom_gate"])
    second["fixtures"]["second_fixture"]["constraints"] = []
    path.write_text(json.dumps(second), encoding="utf-8")

    # Cached data remains stable until the editor/runtime explicitly reloads.
    assert catalog.get("second_fixture") is None
    catalog.reload()
    assert catalog.revision == revision + 1
    assert catalog.get("second_fixture") is not None
    assert catalog.get("custom_gate") is not None


def test_invalid_constraint_anchor_is_rejected(tmp_path):
    document = _custom_document()
    document["fixtures"]["custom_gate"]["constraints"][0]["anchor"] = "missing"
    errors = validate_fixture_document(document)
    assert any("missing anchor" in error for error in errors)

    path = tmp_path / "bad.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(FixtureContentError):
        load_fixture_library(path)
