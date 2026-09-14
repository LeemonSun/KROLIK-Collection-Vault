# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 7.

## Current main / rollback

- Current runtime/CI implementation commit: `2b2499ea807ab179c9805643dddc81602ac28c8f` (`ci: publish stress performance summary`).
- Pre-A1 rollback checkpoint: `checkpoint/pre-a1-render-deform-20260914` at `394a1bf06a4bbaa740b47fce8dec518be53d56bb`.
- No application/schema/data contract changed in this pass.

## Repository integrity status

The validated Python/editor application source (`app.py` and related UI/tests) is still absent, so Python application feature work remains blocked. The canonical recovery transport remains incomplete (`tools/source_restore_parts/part_10.b64` absent); never guess missing source bytes. Vault CI's source-integrity gate remains intentional until restoration.

The Godot runtime tree is independently present and testable, so this pass continued Phase A/A4 runtime performance verification.

## Work completed in pass 7

1. Inspected the previously pending RSS-instrumented Godot Runtime CI run `34801002793`. It completed successfully, so the 512 MiB RSS guard and active 220-agent locomotion harness are now verified rather than merely pending.
2. Kept the existing human-readable `KROLIK_STRESS` output and added a stable machine-readable `KROLIK_STRESS_METRIC` record emitted by `runtime_godot/scripts/stress_harness.gd` with agent count, active count, sample frames/seconds, simulated FPS, moved share, and average travel.
3. Hardened `.github/workflows/godot-runtime.yml` so CI now requires that metric record to exist, publishes the metric plus measured max RSS into the GitHub Actions step summary, and still fails on unparsable RSS, RSS budget regression, or harness failure.
4. Created rollback checkpoint `checkpoint/pre-a1-render-deform-20260914` before the new pass changes.

## Tests / verification actually performed

- Previous RSS-instrumented Godot Runtime CI run `34801002793` for the prior implementation completed **success**. This verifies the Godot import/runtime smoke, active 220-agent locomotion stress and RSS wrapper/budget from pass 6.
- New Godot Runtime CI run `34804620415` for commit `2b2499ea807ab179c9805643dddc81602ac28c8f` started successfully and was **in progress** at state-write time. Therefore this pass does not yet claim the new machine-readable metric parser/step-summary publication as CI-verified.
- New Vault CI run `34804620466` was queued at state-write time. While `app.py` is absent, its green result remains source-integrity status only, not backend/UI verification.
- No Python application tests were run because the validated Python/editor source remains absent.

## Exact blockers / safe continuation

Primary restoration blocker remains a byte-exact copy of the validated stable Python/editor source artifact (or complete exact base64 transport). Do not reconstruct it by guessing.

Next pass should:

1. Inspect Godot Runtime CI run `34804620415` first. If it failed, repair the metric parser/summary before new feature work. If it succeeded, capture the emitted `KROLIK_STRESS_METRIC` and exact `KROLIK_STRESS_PROCESS` RSS value from its logs as the first explicitly recorded Linux/headless active-agent memory baseline.
2. If source is still unavailable, continue A1 visual deformation verification. Build a deterministic Godot test around the existing `VaultSkinnedCharacter`/`Skeleton2D`/`Polygon2D` path that proves a bone transform produces actual mesh/render deformation; prefer image/pixel evidence when a CI-safe renderer is available, otherwise first establish deterministic vertex/bone deformation assertions and then add rendered evidence.
3. Do not call A4 complete until rendered Windows FPS/CPU/memory is measured. Linux/headless CI remains a regression baseline only; tighten the 512 MiB budget only after enough stable samples exist.

## CI semantics until restoration

`Vault CI` distinguishes repository/source integrity from application verification. While `app.py` is absent, green Vault CI means only that recovery state was detected correctly. Godot Runtime CI is independently meaningful for the present `runtime_godot` tree and includes active 220-agent locomotion plus process-RSS regression coverage.
