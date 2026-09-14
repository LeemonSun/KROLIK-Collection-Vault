# AUTONOMOUS STATE

Last updated: 2026-09-14

## Current main

Implementation commit completed this run: `57c4969380ee3cc165bb1cd56e2fbfc2db122ddd` (`test: make stress physics processing explicit`).

Rollback/stable checkpoint already preserved before this harness repair: `checkpoint/stable-stress-collision-isolation-20260914` at `98e1d21aae2e8a4d9a22a28d430ebd73dff8c7ee`. No versioned data contract changed.

## What changed this run

Godot Runtime CI run `34859371617` for prior implementation `0ef46947298d5705ccd92dd99117a689a06817fb` completed red. Download/check, project parse/import, and ordinary headless runtime smoke passed. The 220-agent stress gate reported 220 live agents, 180 real physics frames in 2.9946 s (~60.11 simulated FPS), only 109396 KiB maximum RSS, but zero agents crossing 8 px and only 0.15 px average travel. Therefore time and memory budgets are healthy; movement/physics callback execution remains the failing dimension.

`runtime_godot/scripts/stress_harness.gd` now explicitly calls `set_physics_process(true)` for every dynamically-created `VaultCharacterAgent` in addition to `PROCESS_MODE_INHERIT`. This is important because the harness runs as a custom `SceneTree` via `--script`, without a normal project main scene establishing runtime processing state.

The harness also now records average agent `phase` and final brain-state distribution. `phase` is incremented only inside the production `VaultCharacterAgent._physics_process()`, so a low phase produces a dedicated exit code 5 before the movement assertion. This separates "SceneTree never drove the physics callback" from "physics callback ran but movement logic failed" and prevents another blind CI cycle. The original requirements remain unchanged: 220 agents, 30 warmup physics frames, 180 sample physics frames, <=20 s sample wall time, >=80% travelling >=8 px, and workflow RSS <=512 MiB.

## Tests/checks actually run

No local Python or Godot executable is available through the current connector-only automation environment, so no local tests were claimed.

Verified Godot Runtime CI `34859371617` for `0ef46947298d5705ccd92dd99117a689a06817fb`: Godot download/check PASS; project parse/import PASS; ordinary headless runtime smoke PASS; stress FAIL with `agents=220 active=220 frames=180 seconds=2.9946 avg_fps=60.11 moving=0 moved=0 moved_share=0.000 avg_travel=0.15`; max RSS 109396 KiB; harness exit 4.

Verified Vault CI `34859371672` for the same implementation: SUCCESS.

Immediately after implementation commit `57c4969380ee3cc165bb1cd56e2fbfc2db122ddd`, the Actions runs endpoint had not yet registered a run. Therefore explicit physics-processing activation and the new phase/state diagnostics remain CI-unverified at state-write time.

## Still unverified

- Whether `57c4969380ee3cc165bb1cd56e2fbfc2db122ddd` causes SceneTree to drive all 220 production `_physics_process()` callbacks and restores movement.
- Exact moved-share/state distribution/average phase and RSS for that commit.
- Rendered Windows FPS/CPU/memory remains unmeasured; A4 is not complete from Linux/headless CI alone.
- A1 rendered/deformed geometry regression has not started because failing prior CI still has priority.

`KROLIK_MASTER_PLAN.md` remains absent from the repository, so use the phase ordering preserved in `docs/AUTONOMOUS_RUNBOOK.md` rather than inventing missing roadmap text.

## Blockers/dependencies

- No local Godot executable in this automation environment; Godot verification is via GitHub Actions.
- Validated Python/editor application source remains unavailable in the current repository state, so do not guess or reconstruct missing source bytes.
- `KROLIK_MASTER_PLAN.md` missing from repository.

## Next highest-priority task

1. Inspect Godot Runtime CI for `57c4969380ee3cc165bb1cd56e2fbfc2db122ddd` (or its superseding state commit). If red, use `avg_phase` plus state distribution to distinguish processing from brain/movement failure and repair the concrete production/harness cause without weakening 220 agents, >=80% moved, <=20 s or <=512 MiB requirements.
2. If green, record exact stress metrics and create/update a stable checkpoint branch at the verified commit.
3. Then immediately implement Phase A1: a deterministic Godot regression proving `Skeleton2D`/`Polygon2D` geometry actually deforms when a bone/joint pose changes, rather than merely asserting skinning nodes/data exist. Prefer renderer/runtime evidence and add pixel/render evidence when CI-safe rendering is available.
4. After A1, continue foundation order from the runbook: real pose-model integration, rig migration path, stress/performance completion, clip validation, then data-driven authoring/animation/props/fixtures and reusable sockets/anchors/constraints/occlusion/accessory scene systems.
