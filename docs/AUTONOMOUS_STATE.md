# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 12.

## Current main / rollback

- Current runtime/CI implementation commit: `e61faea362ddf28cf061961cd81254ddd0034ba3` (`ci: make stress harness status capture deterministic`).
- Rollback checkpoint created before this change: `checkpoint/pre-stress-ci-simplify-20260914` at `d82811c198c8aaba1ec9ade257e50f95539bd09a`.
- Earlier rollback checkpoints remain available.
- No application/schema/data contract changed in this pass.

## Repository integrity status

The validated Python/editor application source (`app.py` and related UI/tests) is still absent, so Python application feature work remains blocked. The canonical recovery transport remains incomplete (`tools/source_restore_parts/part_10.b64` absent); never guess missing source bytes. Vault CI's source-integrity gate remains intentional until restoration.

The Godot runtime tree is independently present and testable.

`KROLIK_MASTER_PLAN.md` remains unavailable at the expected root/docs locations; use the phase order preserved in `docs/AUTONOMOUS_RUNBOOK.md` until the roadmap file is restored/found.

## Work completed in pass 12

1. Read `docs/AUTONOMOUS_RUNBOOK.md`, previous state, latest `main`, and current Actions status before editing.
2. Inspected Godot Runtime CI run `34820638528` for `cd1636b1935ebd6ed97daf2842dc2ae2c569353d`: it completed **failure**. Godot download, project parse/import and ordinary headless runtime smoke succeeded; only `220 live-agent stress smoke with RSS budget` failed. Vault CI for that implementation completed success, but remains source-integrity-only while Python/editor source is absent.
3. Created rollback checkpoint `checkpoint/pre-stress-ci-simplify-20260914` from the pre-change main state.
4. Removed the nested child-shell + `tee` status-capture path from the stress step. `/usr/bin/time`/`timeout`/Godot now runs directly with stdout/stderr redirected to a file; `stress_status=$?` is therefore the direct command status, not pipeline state. Captured output and `/usr/bin/time` metrics are printed unconditionally after execution so the normal Actions step log is self-contained.
5. Preserved all real gates: 220 live agents, harness movement/performance assertions, 90 s outer hang guard, and <=512 MiB RSS. No threshold was weakened.
6. Pushed implementation commit `e61faea362ddf28cf061961cd81254ddd0034ba3` to `main`. Godot Runtime CI run `34825544369` and Vault CI run `34825544497` were queued automatically.

## Tests / verification actually performed

- Godot Runtime CI run `34820638528` for the previous implementation: **failure**. Parse/import: success. Ordinary headless runtime smoke: success. 220-agent stress/RSS step: failure.
- Vault CI run `34820638567`: **success**, but this is source-integrity status only while `app.py` is absent.
- Godot Runtime CI run `34825544369` for `e61faea362ddf28cf061961cd81254ddd0034ba3`: **queued** at state-write time. Do not claim the deterministic status-capture repair verified until it completes.
- Vault CI run `34825544497`: **queued** at state-write time.
- No Python application tests were run because validated Python/editor source remains absent.

## Anything still unverified

- Whether run `34825544369` passes the real 220-agent harness/RSS gates.
- If it fails, the exact direct `stress_status`, stress harness output and RSS from that run must be used as the root-cause evidence; do not change timeouts/parsers again without that evidence.
- Exact Linux/headless RSS/FPS baseline from a verified green run.
- Rendered/Windows performance remains unmeasured, so A4 is not complete.

## Exact blockers / safe continuation

Primary restoration blocker remains a byte-exact copy of the validated stable Python/editor source artifact (or complete exact base64 transport). Do not reconstruct it by guessing.

Roadmap-document blocker: `KROLIK_MASTER_PLAN.md` is not discoverable at the expected paths. Do not recreate it from guesses; use the preserved runbook phase order.

Next pass should:

1. Inspect Godot Runtime CI run `34825544369` first. If it failed, use the now-direct `stress_status`, printed harness output and RSS to repair the actual runtime/harness failure. If it succeeded, preserve a stable checkpoint at `e61faea362ddf28cf061961cd81254ddd0034ba3` and record verified metrics.
2. Once CI is green, continue A1: deterministic runtime verification that `VaultSkinnedCharacter`/`Skeleton2D`/`Polygon2D` bone transforms produce actual mesh deformation, followed by rendered/pixel evidence when CI-safe rendering is available.
3. Do not call A4 complete until rendered Windows FPS/CPU/memory is measured. Linux/headless CI is a regression baseline only.

## CI semantics until restoration

`Vault CI` distinguishes repository/source integrity from application verification. While `app.py` is absent, green Vault CI means only that recovery state was detected correctly. Godot Runtime CI is independently meaningful for the present `runtime_godot` tree and includes active 220-agent locomotion plus process-RSS regression coverage.
