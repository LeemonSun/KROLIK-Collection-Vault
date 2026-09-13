from __future__ import annotations

import time
import uuid
from pathlib import Path

import app


def make_app(tmp: Path):
    return app.VaultApp(app.Paths.build(tmp / "DATA"))


def test_catalog_and_stats_handle_500_extra_characters(tmp_path):
    vault = make_app(tmp_path)
    ts = app.now_iso()
    rows = []
    for i in range(500):
        rows.append((
            f"QA{i:04d}", str(uuid.uuid4()), 100 + i // 50, 1, i % 50 + 1,
            f"Scale QA {i}", ts, ts,
        ))
    with vault.db.tx() as con:
        con.executemany(
            "INSERT INTO characters(id,uuid,passage,sheet,position,name,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)",
            rows,
        )

    started = time.perf_counter()
    catalog = vault.db.list_characters()
    catalog_time = time.perf_counter() - started
    started = time.perf_counter()
    stats = vault.db.stats()
    stats_time = time.perf_counter() - started

    assert len(catalog) == 582
    assert stats["total"] == 582
    # Deliberately generous CI guard: catches accidental quadratic/filesystem
    # regressions without turning normal slow runners into flaky failures.
    assert catalog_time < 5.0
    assert stats_time < 2.0


def test_scene_clip_limits_are_enforced_server_side(tmp_path):
    vault = make_app(tmp_path)
    frames = [{"t": 0.0} for _ in range(201)]
    try:
        vault.db.add_scene_clip("F01-C01", "too-many", duration=4.0, data={"keyframes": frames})
        assert False, "201 keyframes must be rejected"
    except ValueError as exc:
        assert "200" in str(exc)
