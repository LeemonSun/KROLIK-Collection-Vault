from __future__ import annotations

from copy import deepcopy
import json

import pytest

from animation_content import (
    ANIMATION_FORMAT_VERSION,
    ANIMATION_SCHEMA,
    AnimationContentError,
    DEFAULT_ANIMATION_LIBRARY_PATH,
    default_animation_document,
    load_animation_library,
    validate_animation_document,
)
from runtime_package import DEFAULT_ANIMATION_GRAPH, DEFAULT_POSE_CLIPS, build_manifest


def test_bundled_animation_library_is_valid_and_is_runtime_source_of_truth():
    loaded = load_animation_library(DEFAULT_ANIMATION_LIBRARY_PATH)
    assert loaded.fallback_used is False
    assert loaded.document["schema"] == ANIMATION_SCHEMA
    assert loaded.document["format_version"] == ANIMATION_FORMAT_VERSION
    assert validate_animation_document(loaded.document) == []
    assert DEFAULT_ANIMATION_GRAPH == loaded.document["state_graph"]
    assert DEFAULT_POSE_CLIPS == loaded.document["clips"]
    assert {"idle_breathe", "walk", "inspect", "social_idle", "contained_idle", "rest", "idle_static"} <= set(loaded.document["clips"])


def test_runtime_manifest_embeds_fresh_external_animation_document():
    manifest = build_manifest(
        character={"id": "hero", "name": "Hero"},
        image_version={"id": 1, "width": 512, "height": 1024, "kind": "cutout"},
        rig={"id": 0, "rest_json": {"joints": {}}, "settings_json": {"bones": []}},
        mind=None,
    )
    animation = manifest["animation"]
    assert animation["schema"] == ANIMATION_SCHEMA
    assert animation["format_version"] == ANIMATION_FORMAT_VERSION
    assert animation["default_clip"] == "idle_breathe"
    assert animation["clips"]["walk"]["duration"] == 0.72

    # A caller can customize one manifest without poisoning the process-global
    # bundled library or future exported characters.
    animation["clips"]["walk"]["duration"] = 99.0
    second = build_manifest(
        character={"id": "hero2"},
        image_version={"id": 2, "width": 512, "height": 1024, "kind": "cutout"},
        rig=None,
        mind=None,
    )
    assert second["animation"]["clips"]["walk"]["duration"] == 0.72


def test_custom_library_can_add_clip_without_runtime_code_change(tmp_path):
    custom = default_animation_document()
    custom["clips"]["wave"] = {
        "duration": 1.0,
        "loop": False,
        "keyframes": [
            {"t": 0.0, "joints": {"right_wrist": [0.0, 0.0]}, "root": {}},
            {"t": 1.0, "joints": {"right_wrist": [0.08, -0.05]}, "root": {}},
        ],
    }
    custom["state_graph"]["greet"] = {"clip": "wave", "loop": False, "blend": 0.12}
    path = tmp_path / "custom.json"
    path.write_text(json.dumps(custom), encoding="utf-8")

    loaded = load_animation_library(path)
    assert validate_animation_document(loaded.document) == []
    assert loaded.document["state_graph"]["greet"]["clip"] == "wave"
    assert loaded.document["clips"]["wave"]["keyframes"][1]["joints"]["right_wrist"] == [0.08, -0.05]


def test_invalid_primary_library_falls_back_to_bundled_asset(tmp_path):
    bad = tmp_path / "bad.json"
    bad.write_text('{"schema":"krolik.animation-library/1","format_version":1,"clips":{}}', encoding="utf-8")

    loaded = load_animation_library(bad, fallback_path=DEFAULT_ANIMATION_LIBRARY_PATH)
    assert loaded.fallback_used is True
    assert loaded.warnings
    assert loaded.document["default_clip"] == "idle_breathe"
    assert validate_animation_document(loaded.document) == []


def test_validator_rejects_non_monotonic_nonfinite_and_missing_clip_refs():
    doc = default_animation_document()
    doc = deepcopy(doc)
    doc["clips"]["walk"]["keyframes"][1]["t"] = doc["clips"]["walk"]["keyframes"][0]["t"]
    doc["clips"]["rest"]["keyframes"][0]["root"]["scale_y"] = float("nan")
    doc["state_graph"]["wander"]["clip"] = "does_not_exist"

    errors = validate_animation_document(doc)
    joined = "\n".join(errors)
    assert "strictly increasing" in joined
    assert "root.scale_y must be finite numeric" in joined
    assert "references missing clip 'does_not_exist'" in joined


def test_invalid_library_without_fallback_fails_loudly(tmp_path):
    path = tmp_path / "invalid.json"
    path.write_text("[]", encoding="utf-8")
    with pytest.raises(AnimationContentError, match="invalid animation library"):
        load_animation_library(path)
