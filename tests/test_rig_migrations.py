from __future__ import annotations

import json

import pytest

from rig_migrations import (
    RigMigrationError,
    migrate_rig_record,
    migrate_rig_storage,
    migrated_record_copy,
)
from rig_tools import DEFAULT_BONES, RIG_FORMAT_VERSION


def test_versionless_rig_migrates_without_dropping_future_joint_or_bone():
    rest = {
        "joints": {
            "head": {"x": 0.5, "y": 0.1},
            "neck": {"x": 0.5, "y": 0.2},
            "cape_anchor": {"x": 0.63, "y": 0.24, "confidence": 0.91},
        },
        "author_note": "legacy custom rig",
    }
    settings = {
        "backend": "manual",
        "bones": [["head", "neck"], ["neck", "cape_anchor"]],
        "custom_solver": {"cape_anchor": "spring"},
    }
    original_rest = json.loads(json.dumps(rest))
    original_settings = json.loads(json.dumps(settings))

    migrated = migrate_rig_storage(rest, settings)

    assert migrated.from_version == 0
    assert migrated.to_version == RIG_FORMAT_VERSION
    assert migrated.applied_steps == ("v0_to_v1",)
    assert migrated.rest["joints"]["cape_anchor"]["confidence"] == 0.91
    assert ["neck", "cape_anchor"] in migrated.settings["bones"]
    assert migrated.settings["custom_solver"]["cape_anchor"] == "spring"
    assert migrated.rest["author_note"] == "legacy custom rig"
    assert rest == original_rest
    assert settings == original_settings


def test_very_old_direct_joint_map_is_wrapped_losslessly():
    direct = {
        "head": {"x": 0.5, "y": 0.1},
        "neck": {"x": 0.5, "y": 0.2},
        "future_face_root": {"x": 0.51, "y": 0.13},
    }
    migrated = migrate_rig_storage(direct, {})
    assert set(migrated.rest["joints"]) == set(direct)
    assert migrated.rest["joints"]["future_face_root"] == direct["future_face_root"]
    assert migrated.settings["bones"] == DEFAULT_BONES
    assert migrated.settings["rig_format_version"] == RIG_FORMAT_VERSION


def test_current_version_migration_is_idempotent_and_preserves_unknown_metadata():
    rest = {"joints": {"tail_root": {"x": 0.5, "y": 0.72}}, "future": {"opaque": [1, 2, 3]}}
    settings = {
        "rig_format_version": RIG_FORMAT_VERSION,
        "bones": [["pelvis", "tail_root"]],
        "future_settings": {"deformer": "custom"},
    }
    first = migrate_rig_storage(rest, settings)
    second = migrate_rig_storage(first.rest, first.settings)
    assert first.applied_steps == ()
    assert second.applied_steps == ()
    assert second.rest == first.rest
    assert second.settings == first.settings


def test_database_record_json_roundtrip_is_non_destructive():
    record = {
        "id": 17,
        "rest_json": json.dumps({"joints": {"head": {"x": 0.5, "y": 0.1}}}),
        "settings_json": json.dumps({"backend": "legacy"}),
        "unrelated_column": "keep-me",
    }
    migrated = migrate_rig_record(record)
    copy = migrated_record_copy(record)

    assert migrated.to_version == RIG_FORMAT_VERSION
    assert copy is not record
    assert copy["id"] == 17
    assert copy["unrelated_column"] == "keep-me"
    assert json.loads(copy["settings_json"])["rig_format_version"] == RIG_FORMAT_VERSION
    assert "rig_format_version" not in json.loads(copy["rest_json"])
    assert "rig_format_version" not in json.loads(record["settings_json"])


def test_newer_rig_is_rejected_instead_of_silent_downgrade():
    future_version = RIG_FORMAT_VERSION + 7
    with pytest.raises(RigMigrationError, match="newer than supported"):
        migrate_rig_storage(
            {"joints": {"head": {"x": 0.5, "y": 0.1}}},
            {"rig_format_version": future_version, "bones": []},
        )


def test_malformed_bone_contract_fails_loudly():
    with pytest.raises(RigMigrationError, match="exactly two"):
        migrate_rig_storage(
            {"joints": {"head": {"x": 0.5, "y": 0.1}}},
            {"rig_format_version": RIG_FORMAT_VERSION, "bones": [["head"]]},
        )
