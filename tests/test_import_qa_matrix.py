from __future__ import annotations

import json
from pathlib import Path

from tools.build_import_qa_matrix import build_import_qa_matrix


def test_import_qa_matrix_covers_formats_alpha_and_proportions(tmp_path: Path) -> None:
    result = build_import_qa_matrix(tmp_path / "matrix")
    assert result["count"] == 4
    entries = result["entries"]
    ids = {entry["character_id"] for entry in entries}
    assert ids == {"qa-alpha-png", "qa-opaque-png", "qa-jpeg", "qa-compact-png"}

    methods = {entry["character_id"]: entry["cutout_method"] for entry in entries}
    assert methods["qa-alpha-png"] == "embedded-alpha"
    assert methods["qa-opaque-png"] == "uniform-border-v1"
    assert methods["qa-jpeg"] == "uniform-border-v1"
    assert methods["qa-compact-png"] == "uniform-border-v1"

    dimensions = {(int(entry["width"]), int(entry["height"])) for entry in entries}
    assert len(dimensions) == 4
    assert all(float(entry["rig_score"]) == 100.0 for entry in entries)
    assert all(int(entry["vertices"]) > 0 for entry in entries)
    assert all(int(entry["triangles"]) > 0 for entry in entries)

    matrix_path = Path(str(result["matrix"]))
    document = json.loads(matrix_path.read_text(encoding="utf-8"))
    assert document["schema"] == "krolik.import-qa-matrix/1"
    assert document["count"] == 4
    for entry in document["entries"]:
        manifest = matrix_path.parent / str(entry["manifest"])
        assert manifest.is_file()
        runtime = json.loads(manifest.read_text(encoding="utf-8"))
        assert runtime["schema"] == "krolik.runtime-character/1"
        assert runtime["quality"]["runtime_ready"] is True
        assert runtime["character"]["id"] == entry["character_id"]
