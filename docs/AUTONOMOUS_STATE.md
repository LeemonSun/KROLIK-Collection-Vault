# KROLIK autonomous development state

Updated: 2026-09-13, autonomous pass 1.

## Validated baseline / rollback

- Pre-recovery main commit: `5df5ad6008df59435cba8b18fe90fca3b7d1cfce`.
- Rollback checkpoint branch created before recovery work: `checkpoint/pre-source-restore-20260913-2356`.
- Current recovery-infrastructure main commit before this state file: `fb396d49024058a94a8735aacf9b450a24047b29`.

## What was found

The repository was not actually in a complete buildable state: the `Vault CI` workflow stopped at `python -m py_compile app.py` because `app.py` was absent from `main`. The same source-tree desynchronization also omitted other stable source/UI/test files that do exist in the latest local stable artifact.

This is a repository synchronization failure, not a failing application unit test. It must be repaired before continuing roadmap Phase A work, otherwise later autonomous passes would build on a misleading red baseline.

## Stable source evidence available to recovery

The latest stable local artifact used as the recovery source is `KROLIK_Collection_Vault_STABLE_2026-09-13_2241.zip`. Before attempting repository recovery it was validated locally with:

- `python -m py_compile app.py` — PASS.
- `PYTHONPATH=. python -m pytest -q` — PASS, **67 passed** (Pillow deprecation warnings only).

A plain system-Python `pytest -q` invocation also exposed a local import-path difference; the verified command above is the one that actually ran the complete suite. CI uses Python 3.12, so CI remains the authoritative cross-environment gate after the files are restored.

## Recovery work completed in this pass

1. Added a source-recovery path and GitHub Actions workflow rather than manually reconstructing large files from snippets.
2. Added `tools/restore_source_bundle.py` with path-traversal protection and ZIP validation.
3. Added `.github/workflows/restore-source.yml`; it restores source, runs `py_compile` + `python -m pytest -q`, and only then commits recovered source to `main`.
4. Tested the recovery path in Actions. This uncovered a connector transport limitation: a single large binary/base64 blob is truncated before reaching GitHub, leaving a ZIP with no central directory.
5. Modified the recovery helper to reject truncated archives and fall back safely instead of silently restoring corrupt data.
6. Began the robust fix: split the exact stable ZIP base64 into small text chunks so the connector cannot truncate the payload. Safe chunk blobs 00–05 have been staged/created during this pass; they are not yet attached to the repository tree because the full set must be committed atomically.

Recovery-related commits currently on main:

- `1a35609072a80178cf776180a3ec84eee37d8bbf` — add recovery bundle/workflow.
- `fe28e11d96c053c146dc4c49f7ef0b6da2892733` — handle text-safe base64 recovery data.
- `fb396d49024058a94a8735aacf9b450a24047b29` — add safe fallback behavior.

## Current verification status

- Latest stable local source: **67/67 tests pass** using the verified command above.
- Repository `Vault CI`: still red because the complete source restoration has not yet landed; do not interpret this as an application regression.
- Recovery workflow: deliberately failed on the truncated single-blob archive, which confirms the guard works and corrupt data was **not** committed.
- No source-format/schema contract was changed in this pass.
- No existing stable application file was overwritten by an unverified recovery attempt.

## Exact blocker / continuation point

Finish the text-safe atomic source upload first. Local files `/mnt/data/chunk_00.txt` … `/mnt/data/chunk_10.txt` were produced from the exact stable recovery ZIP; 11 chunks total (10 × 15000 chars + final 13912 chars). Blobs already created during pass 1 include:

- part 00: `b900ca0d1998e71a95cff24afd1f3acca7bd07e4`
- part 01: `5a8d09266582b5954221918a91322cc43053f49d`
- part 02: `34b1d56e2b9e06c6a2ad11c29877b816736fae44`
- part 03: `daaa039c297654e23221e46e57a603a36bd06bbb`
- part 04: `a4bb5b921e01f5ab8bb518995039679d0bb10049`
- part 05: `fcd2bc45f2fef788e078af0b82937b45dcda61f8`

The next pass should create blobs for parts 06–10, then in **one tree/commit** add all parts under `tools/source_restore_parts/part_00.b64` … `part_10.b64`. Update `tools/restore_source_bundle.py` to concatenate those current chunks first, decode/validate the ZIP, and update the workflow path trigger to include `tools/source_restore_parts/**`.

Then run/inspect `Restore source bundle`. It must only push recovered source after `python -m py_compile app.py` and `python -m pytest -q` pass. After its bot commit, inspect `Vault CI` and `Godot Runtime CI`; fix genuine failures before roadmap work.

Once CI is green, create a stable checkpoint branch such as `checkpoint/stable-source-restored-<timestamp>` and remove or clearly deprecate the known-truncated `tools/source_restore.zip` so future passes cannot mistake it for a valid artifact.

## Next roadmap task after repository integrity is restored

Return to the earliest unblocked Phase A item in `KROLIK_MASTER_PLAN.md`:

1. Prefer **A1 real Godot runtime validation** on real reference art if the runner/assets permit it; capture an actual visual/runtime artifact, not textual asserts.
2. If A1 is blocked by unavailable real reference assets or an unavailable Godot runtime, record the exact blocker and take the next unblocked Phase A task, especially A5 validation-edge coverage or A4 live-agent stress harness/profiling.
3. Do not start B–H content expansion until the Phase A foundation and real runtime gates are trustworthy.
