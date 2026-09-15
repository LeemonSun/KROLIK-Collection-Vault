from __future__ import annotations

import json
from pathlib import Path

from character_import import build_character_runtime_package
from runtime_package_integrity import seal_built_runtime_package, validate_runtime_package_receipt
from tools.build_core_vertical_slice import build_fixture_image
from tools.fanout_runtime_packages import INDEX_SCHEMA, build_fanout


def _template(tmp_path: Path, character_id: str) -> tuple[Path, dict]:
    source = build_fixture_image(tmp_path / character_id / "source.png")
    result = build_character_runtime_package(
        tmp_path / character_id / "project",
        source,
        character_id,
        prefer_ai_rig=False,
    )
    sealed = seal_built_runtime_package(result)
    return Path(str(sealed["package_folder"])), result


def test_fanout_creates_independent_sealed_packages_without_mutating_provenance(tmp_path: Path) -> None:
    template_a, source_a = _template(tmp_path, "template-a")
    template_b, source_b = _template(tmp_path, "template-b")

    report = build_fanout(
        [template_a, template_b],
        tmp_path / "fanout",
        7,
        id_prefix="stress",
    )
    index_path = Path(str(report["index"]))
    index_doc = json.loads(index_path.read_text(encoding="utf-8"))

    assert index_doc["schema"] == INDEX_SCHEMA
    assert index_doc["count"] == 7
    assert len(index_doc["manifests"]) == 7
    assert sorted(index_doc["template_usage"].values()) == [3, 4]

    source_pairs = {
        (source_a["source_sha256"], source_a["cutout_sha256"]),
        (source_b["source_sha256"], source_b["cutout_sha256"]),
    }
    seen_ids: set[str] = set()
    seen_manifest_paths: set[str] = set()
    seen_package_folders: set[str] = set()
    for index, manifest_name in enumerate(index_doc["manifests"]):
        manifest_path = Path(manifest_name)
        package_dir = manifest_path.parent
        expected_id = f"stress_{index:04d}"
        package_receipt = package_dir / "package_receipt.json"
        assert manifest_path.is_file()
        assert package_receipt.is_file()
        reopened = validate_runtime_package_receipt(package_receipt)
        assert reopened["ok"] is True
        assert reopened["character_id"] == expected_id
        assert (reopened["source_sha256"], reopened["cutout_sha256"]) in source_pairs
        assert Path(reopened["manifest"]) == manifest_path.resolve()
        assert Path(reopened["image"]).parent == package_dir.resolve()
        seen_ids.add(reopened["character_id"])
        seen_manifest_paths.add(str(Path(reopened["manifest"])))
        seen_package_folders.add(str(Path(reopened["package_folder"])))

    assert len(seen_ids) == 7
    assert len(seen_manifest_paths) == 7
    assert len(seen_package_folders) == 7

    # Fanout is non-destructive: original template manifests remain their own identities.
    template_a_doc = json.loads((template_a / "manifest.json").read_text(encoding="utf-8"))
    template_b_doc = json.loads((template_b / "manifest.json").read_text(encoding="utf-8"))
    assert template_a_doc["character"]["id"] == "template-a"
    assert template_b_doc["character"]["id"] == "template-b"
