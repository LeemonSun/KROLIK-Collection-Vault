# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 16.

## Current main / rollback

- Current runtime implementation commit: `32ea59b737bb247d7a2ca36a4012633f59037086` (`Fix deterministic stress target setup`).
- Existing rollback checkpoint: `checkpoint/pre-stress-time-exit-fix-20260914` at `3192ec64e17befc198c92b029b13a3650f61101d`.
- No application/schema/data contract changed in this pass.

## Repository integrity status

The validated Python/editor application source (`app.py` and related UI/tests) is still absent, so Python application feature work remains blocked. The canonical recovery transport remains incomplete (`tools/source_restore_parts/part_10.b64` absent); never guess missing source bytes. Vault CI's source-integrity gate remains intentional until restoration.

The Godot runtime tree is independently present and testable.

`KROLIK_MASTER_PLAN.md` remains unavailable at the expected root/docs locations; use the phase order preserved in `docs/AUTONOMOUS_RUNBOOK.md` until the roadmap file is restored/found.

## Work completed in pass 16

1. Read `docs/AUTONOMOUS_RUNBOOK.md`, previous state and latest main/CI before editing.
2. Inspected Godot Runtime CI `34841388794` for implementation `b9b10222a07f7f1128b58850e12ef36a78f2c61d`: verified Godot download, project import and ordinary headless runtime smoke succeeded; only the 220-agent stress/RSS step failed.
3. Stopped changing the shell wrapper and inspected the actual runtime path in `stress_harness.gd` and `character_agent.gd`.
4. Fixed deterministic stress target setup. `VaultCharacterAgent.setup()` intentionally resets `target_position` to spawn, so the harness now assigns its target only after setup and keeps that target within the local stress-grid cell. This prevents the movement assertion from first driving CharacterBody2D agents into the dense grid collision pile while still exercising the real physics/brain/animation path.
5. Pushed coherent single-file implementation commit `32ea59b737bb247d7a2ca36a4012633f59037086` to `main`.

## Tests / verification actually performed

- Godot Runtime CI `34841388794` for prior implementation `b9b10222a07f7f1128b58850e12ef36a78f2c61d`: **failure** only at `220 live-agent stress smoke with RSS budget`; download/import/runtime-smoke steps **passed**.
- Static inspection of `.github/workflows/godot-runtime.yml`, `runtime_godot/scripts/stress_harness.gd`, and `runtime_godot/scripts/character_agent.gd` completed.
- No local Python or Godot executable tests were run in this connector-only pass; do not claim otherwise.
- Immediately after push, GitHub Actions had not yet registered a run for `32ea59b737bb247d7a2ca36a4012633f59037086`; this implementation remains CI-unverified.

## Anything still unverified

- Whether `32ea59b737bb247d7a2ca36a4012633f59037086` passes the 220-agent movement/performance/RSS gates.
- Exact Linux/headless FPS, moved-share and RSS baseline from a verified green run.
- Rendered/Windows performance remains unmeasured, so A4 is not complete.

## Exact blockers / safe continuation

Primary restoration blocker remains a byte-exact copy of the validated stable Python/editor source artifact (or complete exact base64 transport). Do not reconstruct it by guessing.

Roadmap-document blocker: `KROLIK_MASTER_PLAN.md` is not discoverable at expected paths. Do not recreate it from guesses; use the preserved runbook phase order.

The loaded GitHub connector exposed content writes but no branch-creation action in this pass, so no new rollback/stable branch could be created. The implementation is isolated in one commit and can be reverted by SHA. Do not call a stable checkpoint updated until CI is green.

Next pass should:

1. Inspect Godot Runtime CI for `32ea59b737bb247d7a2ca36a4012633f59037086`.
2. If red, use preserved harness/process diagnostics to fix the actual runtime failure without weakening the 220-agent, movement, performance or <=512 MiB RSS gates.
3. If green, record exact FPS/moved-share/RSS, create/update a stable checkpoint if the connector permits it, and immediately continue substantive A1: deterministic proof that `VaultSkinnedCharacter`/`Skeleton2D`/`Polygon2D` bone transforms produce actual mesh deformation, followed by rendered/pixel evidence when CI-safe rendering is available.
4. Do not call A4 complete until rendered Windows FPS/CPU/memory is measured. Linux/headless CI remains a regression baseline only.

## CI semantics until restoration

`Vault CI` distinguishes repository/source integrity from application verification. While `app.py` is absent, green Vault CI means only that recovery state was detected correctly. Godot Runtime CI is independently meaningful for the present `runtime_godot` tree and includes active 220-agent locomotion plus process-RSS regression coverage.
