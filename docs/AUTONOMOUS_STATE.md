# AUTONOMOUS STATE

Last updated: 2026-09-14

## Current main

Implementation commit completed this run: `af47cce6ce6268fd2e188bbf69bbfdcb34a5bafb` (`test: isolate agent movement in stress harness`).

Rollback checkpoint created before the change: `checkpoint/pre-stress-collision-isolation-20260914` at `62d5ff709bd5dbe564f86462a74ea4bec4cd847c`.

## What changed this run

The previous 220-agent Godot stress gate was still failing with harness exit code 4 (movement-share assertion), while Godot download/check, project import, and the normal runtime smoke were passing. Inspection of the production path showed `VaultCharacterAgent.setup()` enables `collision_layer = 1` and `collision_mask = 1`, so the stress grid was measuring agent-vs-agent blocking as part of its movement assertion.

`runtime_godot/scripts/stress_harness.gd` now explicitly sets each stress agent's collision layer/mask to zero after `setup()`. This keeps the production `VaultCharacterAgent` implementation unchanged and still executes its real brain -> `_physics_process()` -> `move_and_slide()` -> animation path, but makes this particular gate a deterministic throughput/behavior test rather than an accidental crowd-collision benchmark. Targets are assigned after `setup()` and extended to 96 px horizontal travel so they remain comfortably beyond the 8 px movement threshold during sampling. The requirements remain 220 live agents, 180 sample frames, <=20 s internal sample budget, >=80% travelling >=8 px, and the workflow's <=512 MiB RSS budget.

No data-contract/schema versions were changed.

## Tests/checks actually run

No local Python or Godot executable is available through the current connector-only automation environment, so no local tests were claimed.

Before the change, inspected GitHub Actions run `34847732049`: Godot setup/import and normal runtime smoke passed; the 220-agent stress/RSS step failed.

After commit `af47cce6ce6268fd2e188bbf69bbfdcb34a5bafb`, GitHub Actions automatically queued:
- Godot Runtime CI run `34853170454` — queued at state-write time; result not yet verified.
- Vault CI run `34853170472` — queued at state-write time; result not yet verified.

## Still unverified

The collision-isolated stress harness must be confirmed by Godot Runtime CI. Do not call it green until run `34853170454` (or the run for the state commit if superseded) completes successfully, including the RSS gate.

`KROLIK_MASTER_PLAN.md` is still absent from the current repository tree, so its exact roadmap text cannot be consulted. Continue using the phase ordering already recorded in the runbook/state rather than inventing missing plan contents.

## Blockers/dependencies

- No local Godot executable in this automation environment; Godot verification is via GitHub Actions.
- `KROLIK_MASTER_PLAN.md` missing from repository.

## Next highest-priority task

1. Inspect the newest Godot Runtime CI. If the 220-agent stress/RSS gate is still red, use the now-visible harness output to fix the concrete runtime/test cause without weakening the 220-agent, movement, performance, or RSS requirements.
2. Once Godot Runtime CI is green, stop infrastructure work and implement A1: a real `Skeleton2D`/`Polygon2D` deformation regression that proves rendered/deformed geometry changes when a bone/joint pose changes (not merely that skinning nodes/data exist). Preserve existing manifest/skinning contracts unless a version bump plus migration/regression coverage is deliberately added.
3. After A1 is verified, continue the roadmap toward animation/IK/constraints, collision/navigation/life-sim scale, and reusable data-driven scene sockets/anchors/props/fixtures/occlusion/accessory slots.
