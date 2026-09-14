# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 13.

## Current main / rollback

- Current runtime/CI implementation commit: `eeeb6e085064e097af1c33d80c7394ff07d8b6d9` (`ci: preserve Godot stress exit status through time`).
- Rollback checkpoint created before this change: `checkpoint/pre-fix-stress-godot-status-20260914` at `aab89c8610ecdf38b7c55aafa8910fb5f89fdedd`.
- Earlier rollback checkpoints remain available.
- No application/schema/data contract changed in this pass.

## Repository integrity status

The validated Python/editor application source (`app.py` and related UI/tests) is still absent, so Python application feature work remains blocked. The canonical recovery transport remains incomplete (`tools/source_restore_parts/part_10.b64` absent); never guess missing source bytes. Vault CI's source-integrity gate remains intentional until restoration.

The Godot runtime tree is independently present and testable.

`KROLIK_MASTER_PLAN.md` remains unavailable at the expected root/docs locations; use the phase order preserved in `docs/AUTONOMOUS_RUNBOOK.md` until the roadmap file is restored/found.

## Work completed in pass 13

1. Read `docs/AUTONOMOUS_RUNBOOK.md`, previous state, latest `main`, and current Actions status before editing.
2. Inspected Godot Runtime CI run `34825544369` for `e61faea362ddf28cf061961cd81254ddd0034ba3`. It failed only at the 220-agent stress/RSS step; project import and ordinary runtime smoke succeeded.
3. Inspected the job log and identified the concrete CI-wrapper failure: GNU `/usr/bin/time` reports the wrapped Godot command's nonzero status through its own exit code. The workflow needs to preserve that exact status while keeping diagnostics available; the previous nested/pipeline experiments obscured the distinction.
4. Created rollback checkpoint `checkpoint/pre-fix-stress-godot-status-20260914` from pre-change main.
5. Kept the direct `/usr/bin/time -> timeout -> Godot` execution path and documented/enforced capture of its exact exit status before re-enabling shell errexit. Output and RSS diagnostics remain unconditional. No runtime threshold or data contract was changed.
6. Pushed implementation commit `eeeb6e085064e097af1c33d80c7394ff07d8b6d9` to `main`. Godot Runtime CI run `34832236322` and Vault CI run `34832236349` were queued automatically.

## Tests / verification actually performed

- Godot Runtime CI run `34825544369` for previous implementation: **failure**. Download/import: success. Ordinary headless runtime smoke: success. 220-agent stress/RSS step: failure.
- Vault CI run `34825544497` for previous implementation: **success**, but source-integrity-only while Python/editor source is absent.
- Godot Runtime CI run `34832236322` for `eeeb6e085064e097af1c33d80c7394ff07d8b6d9`: **queued** at state-write time. Do not claim the repair verified until it completes.
- Vault CI run `34832236349`: **queued** at state-write time.
- No Python application tests were run because validated Python/editor source remains absent.

## Anything still unverified

- Whether Godot Runtime CI run `34832236322` passes the real 220-agent harness/RSS gates.
- If it fails, use its now-unconditional stress output, exact process status and `/usr/bin/time` RSS as the only root-cause evidence before another change.
- Exact Linux/headless RSS/FPS baseline from a verified green run.
- Rendered/Windows performance remains unmeasured, so A4 is not complete.

## Exact blockers / safe continuation

Primary restoration blocker remains a byte-exact copy of the validated stable Python/editor source artifact (or complete exact base64 transport). Do not reconstruct it by guessing.

Roadmap-document blocker: `KROLIK_MASTER_PLAN.md` is not discoverable at expected paths. Do not recreate it from guesses; use the preserved runbook phase order.

Next pass should:

1. Inspect Godot Runtime CI run `34832236322` first. If failed, repair the actual harness/runtime cause using its printed status/output/RSS. If green, create a stable checkpoint at the verified implementation/state commit and record the measured metrics.
2. Once CI is green, continue A1: deterministic verification that `VaultSkinnedCharacter`/`Skeleton2D`/`Polygon2D` bone transforms produce actual mesh deformation, then add rendered/pixel evidence when CI-safe rendering is available.
3. Do not call A4 complete until rendered Windows FPS/CPU/memory is measured. Linux/headless CI remains a regression baseline only.

## CI semantics until restoration

`Vault CI` distinguishes repository/source integrity from application verification. While `app.py` is absent, green Vault CI means only that recovery state was detected correctly. Godot Runtime CI is independently meaningful for the present `runtime_godot` tree and includes active 220-agent locomotion plus process-RSS regression coverage.
