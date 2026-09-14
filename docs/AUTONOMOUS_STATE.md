# AUTONOMOUS STATE

Last updated: 2026-09-14 21:04 +03:00

## Current verified implementation

Latest verified code/test commit: `60a8ce82e220d44433d1e0f7250db3a05cd71acc` (`test: run life sim regression suite`).

Stable checkpoint for this block: `checkpoint/stable-d1-life-sim-source-parity-20260914-2103`.
Rollback checkpoint: `checkpoint/pre-d1-life-sim-parity-20260914-2101`.

Earlier verified checkpoints remain intact through `checkpoint/stable-c5-facial-mood-20260914-2102`.

No versioned rig/skin/animation contract changed. Rig remains v1; animation library remains `krolik.animation-library/1`, format v1.

## Phase status

- Phase A: A1/A3/A5 verified; A4 Linux/headless verified; A2 blocked on validated DWPose/RTMPose ONNX model; rendered Windows 200–500-agent measurement still pending.
- Phase B: external animation/fixture/pose content pipeline verified; legacy graphical UI integration blocked because validated `app.py` is absent.
- Phase C: complete for current source-asset capabilities: 33-clip motion library, angle-limited IK, additive layers, production secondary motion, semantic facial/mood state.
- Phase D: D1 IN PROGRESS. This run repaired a real semantic drift between Python `life_sim.py` and Godot `agent_brain.gd`: Python now contains the richer utility scoring/routine/return-home policy already used by the runtime, so the documented Python source of truth no longer silently drops `routine` or uses the obsolete threshold-only chooser.

## D1 work verified this run

`life_sim.py` now:
- validates/preserves `routine` (`balanced`, `homebody`, `explorer`, `social`);
- exposes the same utility-score families and bonuses used by `VaultAgentBrain`;
- applies the same hard mobility/contained/rest/return-home gates and utility tie-break order;
- returns utility telemetry while preserving existing mind snapshot fields;
- keeps existing need-decay/recovery rates and animation mapping.

`tests/test_life_sim.py` adds regressions for profile validation, hard mobility gates, return-home behavior, context/routine utility decisions, and snapshot compatibility.

CI initially did not execute the new test because Vault CI had an explicit test allowlist. Commit `60a8ce82e220d44433d1e0f7250db3a05cd71acc` fixes that omission by adding `tests/test_life_sim.py` to the core suite.

## Tests/checks actually run

No local execution is claimed; verification came from GitHub Actions.

Vault CI run `34878405347` for `60a8ce82e220d44433d1e0f7250db3a05cd71acc`:
- source-integrity: PASS;
- core module syntax: PASS;
- content validator: PASS (`files=3 failed=0`);
- core regression suite: PASS, `48 passed`;
- backend/UI: SKIPPED because validated `app.py` remains absent.

The immediately preceding run `34878313228` also passed 44 legacy core tests, but it did not include the new life-sim test; this was corrected before declaring the block verified.

Godot CI was not triggered by this Python/CI-only block and no new Godot runtime result is claimed. Existing C5 Godot Runtime CI `34878051171` remains the latest verified runtime reference: project parse/import, headless smoke, animation/layer/facial/secondary/IK/deformation gates and 220-agent stress all passed; stress had 220/220 moved, `facial_active=220`, sim_fps `59.83`, max RSS about 110 MiB.

## Still blocked / unverified

- A2 real DWPose/RTMPose accuracy: no validated ONNX model artifact/source.
- Final rendered Windows FPS/CPU/memory at 200–500 characters remains unmeasured.
- Validated legacy `app.py` is unavailable; backend/UI and direct graphical editor integration remain blocked.
- `KROLIK_MASTER_PLAN.md` remains absent; follow `docs/AUTONOMOUS_RUNBOOK.md`.
- Dedicated eyelid/eye/mouth geometry is not present; facial eye/mouth values remain semantic channels.
- D1 is not complete yet: Python and Godot formulas are now intentionally aligned, but there is still no generated/versioned source-independent AI policy document or cross-runtime parity harness preventing future drift.

## Next highest-priority task

Finish D1 rather than starting personality breadth:
1. Export a versioned AI policy document from Python-owned constants/semantics without changing existing runtime mind snapshots.
2. Make `VaultAgentBrain` load that policy with deterministic built-in fallback when missing/invalid; runtime must not require Python.
3. Add Python export validation plus a Godot parity harness using representative profiles/needs/contexts so Python/Godot state decisions cannot silently diverge again.
4. Add `life_sim.py`/policy paths to Godot Runtime CI triggers, run both Vault and Godot CI, and only then mark D1 complete.
