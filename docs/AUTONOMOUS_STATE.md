# AUTONOMOUS STATE

Last updated: 2026-09-14

## Current main

Implementation commit completed this run: `0ef46947298d5705ccd92dd99117a689a06817fb` (`test: run stress agents on real physics frames`).

Rollback checkpoint created before the change: `checkpoint/pre-stress-brain-determinism-20260914` at `98e1d21aae2e8a4d9a22a28d430ebd73dff8c7ee`.

## What changed this run

Godot Runtime CI run `34853170454` for prior implementation `af47cce6ce6268fd2e188bbf69bbfdcb34a5bafb` completed red. Godot download/check, project parse/import, and ordinary headless runtime smoke all passed; only `220 live-agent stress smoke with RSS budget` failed.

Inspection found a deeper harness validity problem: the stress harness set every `VaultCharacterAgent` to `PROCESS_MODE_DISABLED` and then invoked `_physics_process()` manually from a tight deferred loop. That bypasses the intended SceneTree physics-frame context for `CharacterBody2D.move_and_slide()`, so the movement assertion was not a trustworthy test of the production physics path.

`runtime_godot/scripts/stress_harness.gd` now keeps agents on normal `PROCESS_MODE_INHERIT` and advances warmup/sample windows by awaiting real `physics_frame` signals. The SceneTree therefore drives the production `_physics_process()` method, including brain selection, CharacterBody2D `move_and_slide()`, animation sampling and visual update. Agent-vs-agent collisions remain isolated for this throughput/behavior gate. Deterministic post-setup targets and all existing requirements remain: 220 live agents, 30 warmup physics frames, 180 sampled physics frames, <=20 s sample wall time, >=80% travelling >=8 px, plus the workflow's <=512 MiB RSS gate.

No data-contract/schema versions changed.

## Tests/checks actually run

No local Python or Godot executable is available through the current connector-only automation environment, so no local tests were claimed.

Verified GitHub Actions run `34853170454` for `af47cce6ce6268fd2e188bbf69bbfdcb34a5bafb`: download/check PASS; project parse/import PASS; ordinary headless runtime smoke PASS; 220-agent stress/RSS step FAIL.

Vault CI for the prior state commit `98e1d21aae2e8a4d9a22a28d430ebd73dff8c7ee`, run `34853216325`, completed SUCCESS.

Immediately after implementation commit `0ef46947298d5705ccd92dd99117a689a06817fb`, the Actions runs endpoint had not yet registered a new run. Therefore the real-physics-frame harness remains CI-unverified at state-write time.

## Still unverified

- Whether `0ef46947298d5705ccd92dd99117a689a06817fb` passes the 220-agent movement/performance/RSS gate.
- Exact moved-share, sample time/FPS and RSS from a green run.
- Rendered Windows FPS/CPU/memory remains unmeasured; A4 is not complete from Linux/headless CI alone.
- A1 rendered/deformed geometry regression has not started because failing prior CI was fixed first.

`KROLIK_MASTER_PLAN.md` remains absent from the repository, so use the phase ordering preserved in `docs/AUTONOMOUS_RUNBOOK.md` rather than inventing missing roadmap text.

## Blockers/dependencies

- No local Godot executable in this automation environment; Godot verification is via GitHub Actions.
- Validated Python/editor application source remains unavailable in the current repository state, so do not guess or reconstruct missing source bytes.
- `KROLIK_MASTER_PLAN.md` missing from repository.

## Next highest-priority task

1. Inspect Godot Runtime CI for implementation `0ef46947298d5705ccd92dd99117a689a06817fb` (or the superseding state commit). If red, use the concrete failing step/output to repair the production/harness cause without weakening 220 agents, >=80% moved, <=20 s or <=512 MiB RSS requirements.
2. If green, record exact stress metrics and create/update a stable checkpoint branch at the verified commit.
3. Then immediately implement Phase A1: a deterministic Godot regression proving `Skeleton2D`/`Polygon2D` geometry actually deforms when a bone/joint pose changes, rather than merely asserting skinning nodes/data exist. Prefer renderer/runtime evidence and add pixel/render evidence when CI-safe rendering is available.
4. After A1, continue foundation order from the runbook: real pose-model integration, rig migration path, stress/performance completion, clip validation, then data-driven authoring/animation/props/fixtures and reusable sockets/anchors/constraints/occlusion/accessory scene systems.
