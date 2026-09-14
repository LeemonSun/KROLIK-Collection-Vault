# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 11.

## Current main / rollback

- Current runtime/CI implementation commit: `cd1636b1935ebd6ed97daf2842dc2ae2c569353d` (`ci: preserve stress harness exit status through tee`).
- New rollback checkpoint created before this change: `checkpoint/pre-stress-exit-diagnostic-20260914` at `e1a35c65a70e3e9768c9c8edc71b59b43b747b20`.
- Earlier rollback checkpoints remain available.
- No application/schema/data contract changed in this pass.

## Repository integrity status

The validated Python/editor application source (`app.py` and related UI/tests) is still absent, so Python application feature work remains blocked. The canonical recovery transport remains incomplete (`tools/source_restore_parts/part_10.b64` absent); never guess missing source bytes. Vault CI's source-integrity gate remains intentional until restoration.

The Godot runtime tree is independently present and testable.

`KROLIK_MASTER_PLAN.md` was not found at repository root or `docs/KROLIK_MASTER_PLAN.md` in this pass, and repository code search returned no match. Continue using the phase order already preserved in this state/runbook until the roadmap file is restored/found; record this as a repository documentation blocker rather than inventing its contents.

## Work completed in pass 11

1. Read `docs/AUTONOMOUS_RUNBOOK.md`, previous `docs/AUTONOMOUS_STATE.md`, latest main commits and current Actions state before editing.
2. Inspected Godot Runtime CI run `34819317736` for implementation commit `cfec1162ce8ebec11a423e4b523e651ae97c6f5d`. It completed **failure**. Download, project parse/import and ordinary headless runtime smoke all succeeded; only `220 live-agent stress smoke with RSS budget` failed after about six seconds. Therefore the previous 90-second watchdog change did not fix the failure and the process was not simply exhausting that watchdog.
3. Created rollback checkpoint `checkpoint/pre-stress-exit-diagnostic-20260914` before modifying CI.
4. Reworked the stress-step process-status capture so the timed Godot command persists its own exit code to a status file inside a child shell, independently of the outer `tee` pipeline. The workflow now reports both `process_status` and `pipeline_status`, validates the persisted status, and always prints the captured stress-log tail on any non-zero Godot/harness status.
5. Kept the actual correctness/performance gates unchanged: the harness still requires all 220 agents live, >=80% travelling at least 8 px, <=20 s for the measured 180-frame sample; CI still requires maximum RSS <=512 MiB and a zero harness process exit.
6. Pushed implementation commit `cd1636b1935ebd6ed97daf2842dc2ae2c569353d` to `main`. Godot Runtime CI run `34820638528` and Vault CI run `34820638567` started automatically.

## Tests / verification actually performed

- Godot Runtime CI run `34819317736` for `cfec1162ce8ebec11a423e4b523e651ae97c6f5d`: **failure**. Project parse/import: success. Ordinary headless runtime smoke: success. 220-agent stress/RSS step: failure. The failing step completed in roughly six seconds, ruling out the configured 90-second outer watchdog as the immediate cause.
- Godot Runtime CI run `34820638528` for `cd1636b1935ebd6ed97daf2842dc2ae2c569353d`: **in progress** at state-write time. Do not claim the status-capture repair verified until it completes.
- Vault CI run `34820638567`: queued/in progress at state-write time. While `app.py` is absent, green Vault CI is source-integrity status only, not backend/UI verification.
- No Python application tests were run because validated Python/editor source remains absent.

## Anything still unverified

- Exact Godot/harness exit code and captured output responsible for run `34819317736`; the available connector exposes step conclusions but not the Actions log archive. The new workflow deliberately makes the next failure self-describing in normal step output/summary.
- Whether run `34820638528` passes the real harness-exit/RSS gates.
- Exact Linux/headless RSS/FPS baseline from a verified green run.
- Rendered/Windows performance remains unmeasured, so A4 is not complete.

## Exact blockers / safe continuation

Primary restoration blocker remains a byte-exact copy of the validated stable Python/editor source artifact (or complete exact base64 transport). Do not reconstruct it by guessing.

Roadmap-document blocker: `KROLIK_MASTER_PLAN.md` is currently not discoverable at the expected root/docs paths or by repository search. Do not recreate its priorities from guesses; use the preserved phase order in autonomous state/runbook until recovered.

Next pass should:

1. Inspect Godot Runtime CI run `34820638528` first. If it failed, use the persisted `process_status`, `pipeline_status`, RSS and captured tail to fix the actual harness/runtime problem rather than changing timeouts/parsers again. If it succeeded, record verified RSS/FPS/process status and create/update a stable checkpoint at the verified implementation commit.
2. Once CI is green, continue A1 visual deformation verification: deterministic test around `VaultSkinnedCharacter`/`Skeleton2D`/`Polygon2D` proving a bone transform produces actual mesh deformation, then rendered/pixel evidence when CI-safe rendering is available.
3. Do not call A4 complete until rendered Windows FPS/CPU/memory is measured. Linux/headless CI remains a regression baseline only.

## CI semantics until restoration

`Vault CI` distinguishes repository/source integrity from application verification. While `app.py` is absent, green Vault CI means only that recovery state was detected correctly. Godot Runtime CI is independently meaningful for the present `runtime_godot` tree and includes active 220-agent locomotion plus process-RSS regression coverage.
