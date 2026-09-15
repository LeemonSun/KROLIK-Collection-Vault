from __future__ import annotations

from copy import deepcopy
import json

import pytest

from prop_content import FixtureCatalog
from room_content import (
    ROOM_FORMAT_VERSION,
    ROOM_SCHEMA,
    RoomCatalog,
    RoomContentError,
    load_room_library,
    validate_room_document,
    validate_room_fixture_references,
)


def _custom_document() -> dict:
    return {
        "schema": ROOM_SCHEMA,
        "format_version": ROOM_FORMAT_VERSION,
        "rooms": {
            "custom_room": {
                "category": "test",
                "tags": ["test", "anchor"],
                "dimensions": {"w": 8.0, "h": 6.0},
                "theme": {
                    "floor_rgb": [0.1, 0.12, 0.14],
                    "border_rgb": [0.3, 0.32, 0.34],
                    "accent_rgb": [0.6, 0.5, 0.4],
                    "ambient": 0.3,
                    "fog": 0.1,
                },
                "navigation": {"padding": 0.5, "doorway_width": 1.2},
                "capacity": 2,
                "fixture_compatibility": {
                    "allowed_fixture_tags": ["anchor"],
                    "preferred_fixture_kinds": ["chain_anchor"],
                },
                "placement_slots": [
                    {"id": "subject", "x": 0.5, "y": 0.65, "role": "character", "accepts": ["character"]},
                    {"id": "fixture", "x": 0.5, "y": 0.35, "role": "fixture", "accepts": ["fixture"]},
                ],
                "builtins": [{"fixture": "chain_anchor", "slot": "fixture"}],
            }
        },
    }


def test_bundled_room_catalog_is_large_varied_and_fixture_valid():
    catalog = RoomCatalog()
    assert catalog.revision == 1
    assert len(catalog.kinds()) >= 14
    assert {
        "storage_cell", "stone_cell", "observation_room", "chain_hall",
        "shackle_room", "restraint_room", "cage_gallery", "frame_gallery",
        "iron_post_chamber", "archive_gallery", "quarantine_lab", "deep_vault",
    }.issubset(catalog.kinds())
    assert validate_room_document(catalog.document) == []
    assert validate_room_fixture_references(catalog.document) == []

    themes = {
        tuple(catalog.get(kind)["theme"]["floor_rgb"])
        for kind in catalog.kinds()
    }
    assert len(themes) >= 10


def test_room_slots_are_unique_normalized_and_product_useful():
    catalog = RoomCatalog()
    total_character_slots = 0
    total_fixture_slots = 0
    for kind in catalog.kinds():
        room = catalog.get(kind)
        assert room is not None
        slots = room["placement_slots"]
        ids = [slot["id"] for slot in slots]
        assert len(ids) == len(set(ids))
        for slot in slots:
            assert 0.0 <= slot["x"] <= 1.0
            assert 0.0 <= slot["y"] <= 1.0
            if slot["role"] == "character":
                total_character_slots += 1
            if slot["role"] == "fixture":
                total_fixture_slots += 1
    assert total_character_slots >= 20
    assert total_fixture_slots >= 25


def test_fixture_compatibility_uses_real_fixture_tags_and_kinds():
    rooms = RoomCatalog()
    fixtures = FixtureCatalog()
    assert rooms.supports_fixture("chain_hall", "hanging_chains", fixtures)
    assert rooms.supports_fixture("chain_hall", "chain_anchor", fixtures)
    assert not rooms.supports_fixture("chain_hall", "barrel", fixtures)
    assert rooms.supports_fixture("cage_gallery", "standing_cage", fixtures)
    assert rooms.supports_fixture("frame_gallery", "x_frame", fixtures)
    assert rooms.capacity("archive_gallery") == 6


def test_room_fixture_reference_validation_catches_unknown_content():
    document = _custom_document()
    document["rooms"]["custom_room"]["builtins"][0]["fixture"] = "missing_fixture"
    errors = validate_room_fixture_references(document)
    assert any("unknown builtin fixture" in error for error in errors)


def test_room_validation_rejects_bad_slot_and_theme(tmp_path):
    document = _custom_document()
    broken = deepcopy(document["rooms"]["custom_room"]["placement_slots"][0])
    broken["x"] = 2.0
    document["rooms"]["custom_room"]["placement_slots"].append(broken)
    document["rooms"]["custom_room"]["theme"]["accent_rgb"] = [2.0, 0.0, 0.0]
    errors = validate_room_document(document)
    assert any("duplicate placement slot" in error for error in errors)
    assert any("must be finite in [0, 1]" in error for error in errors)
    assert any("accent_rgb" in error for error in errors)

    path = tmp_path / "bad_rooms.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(RoomContentError):
        load_room_library(path)


def test_room_catalog_reload_is_explicit(tmp_path):
    path = tmp_path / "rooms.json"
    first = _custom_document()
    path.write_text(json.dumps(first), encoding="utf-8")
    catalog = RoomCatalog(path)
    assert catalog.get("second") is None
    revision = catalog.revision

    second = deepcopy(first)
    second["rooms"]["second"] = deepcopy(second["rooms"]["custom_room"])
    second["rooms"]["second"]["builtins"] = []
    path.write_text(json.dumps(second), encoding="utf-8")
    assert catalog.get("second") is None
    catalog.reload()
    assert catalog.revision == revision + 1
    assert catalog.get("second") is not None
