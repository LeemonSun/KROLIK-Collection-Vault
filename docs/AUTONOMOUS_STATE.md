# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 8.

## Current main / rollback

- Current runtime/CI implementation commit: `8c66a3630c7f56a96c76e2627771cfd18ae40138` (`ci: parse Godot stress metric with engine prefix`).
- Rollback checkpoint for this repair: `checkpoint/pre-fix-stress-metric-20260914` at `2b2499ea807ab179c9805643dddc81602ac28c8f`.
- Earlier pre-A1 rollback checkpoint remains `checkpoint/pre-a1-render-deform-20260914` at `394a1bf06a4bbaa740b47fce8dec518be53d56bb`.
- No application/schema/data contract changed in this pass.

## Repository integrity status

The validated Python/editor application source (`app.py` and related UI/tests) is still absent, so Python application feature work remains blocked. The canonical recovery transport remains incomplete (`tools/source_restore_parts/part_10.b64` absent); never guess missing source bytes. Vault CI's source-integrity gate remains intentional until restoration.

The Godot runtime tree is independently present and testable.

## Work completed in pass 8

1. Inspected the pending Godot Runtime CI run `34804620415` from pass 7. It completed **failure**, specifically in step `220 live-agent stress smoke with RSS budget`; project import and ordinary headless runtime smoke both succeeded.
2. Treated that failing prior work as the highest-priority task, before beginning A1.
3. Identified the fragile parser: workflow required `KROLIK_STRESS_METRIC` at column zero even though Godot/logging may prefix stdout lines. The harness itself emits the stable marker.
4. Hardened `.github/workflows/godot-runtime.yml` to find the stable marker anywhere in a line, strip only any engine/log prefix before the marker, and dump available `KROLIK_STRESS` lines on future parse failure for diagnosability.
5. Created rollback checkpoint `checkpoint/pre-fix-stress-metric-20260914` before changing CI.

## Tests / verification actually performed

- Godot Runtime CI run `34804620415` for previous commit `2b2499ea807ab179c9805643dddc81602ac28c8f`: **failure**. `Parse and import Godot project`: success. `Headless runtime smoke`: success. `220 live-agent stress smoke with RSS budget`: failure.
- New Godot Runtime CI run `34809872076` for repair commit `8c66a3630c7f56a96c76e2627771cfd18ae40138`: **in progress** at state-write time. Do not claim the parser repair verified until this run completes.
- New Vault CI run `34809872084` was queued at inspection time. While `app.py` is absent, a green result is source-integrity status only, not backend/UI verification.
- No Python application tests were run because validated Python/editor source remains absent.

## Exact blockers / safe continuation

Primary restoration blocker remains a byte-exact copy of the validated stable Python/editor source artifact (or complete exact base64 transport). Do not reconstruct it by guessing.

Next pass should:

1. Inspect Godot Runtime CI run `34809872076` first. If it failed, inspect the stress step and repair before feature work. If it succeeded, record its exact `KROLIK_STRESS_METRIC` and `KROLIK_STRESS_PROCESS` RSS baseline if accessible.
2. Once CI is green, continue A1 visual deformation verification. Build a deterministic Godot test around the existing `VaultSkinnedCharacter`/`Skeleton2D`/`Polygon2D` path that proves a bone transform produces actual mesh/render deformation; prefer image/pixel evidence when a CI-safe renderer is available, otherwise establish deterministic geometry deformation assertions first and add rendered evidence next.
3. Do not call A4 complete until rendered Windows FPS/CPU/memory is measured. Linux/headless CI remains a regression baseline only.

## CI semantics until restoration

`Vault CI` distinguishes repository/source integrity from application verification. While `app.py` is absent, green Vault CI means only that recovery state was detected correctly. Godot Runtime CI is independently meaningful for the present `runtime_godot` tree and includes active 220-agent locomotion plus process-RSS regression coverage.
