# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 14.

## Current main / rollback

- Current runtime/CI implementation commit: `3192ec64e17befc198c92b029b13a3650f61101d` (`Fix stress harness shell exit capture`).
- Rollback checkpoint created before this change: `checkpoint/pre-stress-shell-fix-20260914` at `41b4b7896f9a9d9dcf5a980eb3b3bb58550412ed`.
- Earlier rollback checkpoints remain available.
- No application/schema/data contract changed in this pass.

## Repository integrity status

The validated Python/editor application source (`app.py` and related UI/tests) is still absent, so Python application feature work remains blocked. The canonical recovery transport remains incomplete (`tools/source_restore_parts/part_10.b64` absent); never guess missing source bytes. Vault CI's source-integrity gate remains intentional until restoration.

The Godot runtime tree is independently present and testable.

`KROLIK_MASTER_PLAN.md` remains unavailable at the expected root/docs locations; use the phase order preserved in `docs/AUTONOMOUS_RUNBOOK.md` until the roadmap file is restored/found.

## Work completed in pass 14

1. Read `docs/AUTONOMOUS_RUNBOOK.md`, previous state, latest `main`, and current Actions status before editing.
2. Inspected Godot Runtime CI run `34832236322`: project import and ordinary headless runtime smoke succeeded; only the 220-agent stress/RSS step failed.
3. Created rollback checkpoint `checkpoint/pre-stress-shell-fix-20260914` before changing CI.
4. Simplified the stress wrapper's shell semantics: the step now runs without `errexit` while `/usr/bin/time -> timeout -> Godot` executes, captures `$?` immediately as `stress_status`, and reports `KROLIK_STRESS_PROCESS_STATUS` before evaluating RSS/harness gates. This removes the remaining ambiguity around `set +e`/`set -e` transitions without weakening any runtime assertion.
5. Kept the 220-agent harness, movement/performance assertions, 90-second outer watchdog and 512 MiB RSS budget unchanged.
6. Pushed implementation commit `3192ec64e17befc198c92b029b13a3650f61101d` to `main`.

## Tests / verification actually performed

- Godot Runtime CI run `34832236322` for the previous implementation: **failure**. Download/import: success. Ordinary headless runtime smoke: success. 220-agent stress/RSS step: failure.
- New Godot Runtime CI run `34837762333` for `3192ec64e17befc198c92b029b13a3650f61101d`: **in progress** at state-write time; do not claim it passed.
- New Vault CI run `34837762335`: **queued** at state-write time.
- No local Python/Godot tests were run in this pass because the connector provides repository/Actions access rather than a local executable checkout, and validated Python/editor source remains absent.

## Anything still unverified

- Whether Godot Runtime CI `34837762333` passes the real 220-agent harness/RSS gates.
- Exact Linux/headless RSS/FPS baseline from a verified green run.
- Rendered/Windows performance remains unmeasured, so A4 is not complete.

## Exact blockers / safe continuation

Primary restoration blocker remains a byte-exact copy of the validated stable Python/editor source artifact (or complete exact base64 transport). Do not reconstruct it by guessing.

Roadmap-document blocker: `KROLIK_MASTER_PLAN.md` is not discoverable at expected paths. Do not recreate it from guesses; use the preserved runbook phase order.

Next pass should:

1. Inspect Godot Runtime CI `34837762333` first. If red, use `KROLIK_STRESS_PROCESS_STATUS`, captured harness output and RSS to repair the actual failure without weakening assertions/budgets. If green, create/update a stable checkpoint at the verified implementation/state commit and record measured metrics.
2. Once stress CI is green, stop spending passes on CI plumbing and continue substantive A1: deterministic proof that `VaultSkinnedCharacter`/`Skeleton2D`/`Polygon2D` bone transforms produce actual mesh deformation, followed by rendered/pixel evidence when CI-safe rendering is available.
3. Do not call A4 complete until rendered Windows FPS/CPU/memory is measured. Linux/headless CI remains a regression baseline only.

## CI semantics until restoration

`Vault CI` distinguishes repository/source integrity from application verification. While `app.py` is absent, green Vault CI means only that recovery state was detected correctly. Godot Runtime CI is independently meaningful for the present `runtime_godot` tree and includes active 220-agent locomotion plus process-RSS regression coverage.
