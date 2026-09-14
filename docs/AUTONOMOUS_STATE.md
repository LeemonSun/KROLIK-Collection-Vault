# AUTONOMOUS STATE

Last updated: 2026-09-14 21:03 +03:00

## Current verified implementation

Latest verified code/test commit: `28924b4e918f496ccfb171b4c9440485dc9f1d31` (`test: gate facial mood runtime behavior`).

Verified stable checkpoints:
- `checkpoint/stable-nav-fallback-stress-20260914-1952` — A4 220-agent Linux/headless movement/performance.
- `checkpoint/stable-a1-rendered-deformation-20260914-1956` — A1 real rendered Skeleton2D/Polygon2D deformation.
- `checkpoint/stable-a3-rig-migrations-20260914-2002` — A3 non-destructive rig migrations.
- `checkpoint/stable-a5-animation-validation-20260914-2006` — A5 malformed-animation isolation.
- `checkpoint/stable-b1-external-animation-content-20260914-2011` — B1 external animation content.
- `checkpoint/stable-b2-fixture-content-20260914-2020` — B2 data-driven fixtures/anchors/constraints.
- `checkpoint/stable-b3-pose-library-20260914-2024` — B3 reusable pose library/authoring services.
- `checkpoint/stable-c1-motion-library-20260914-2028` — C1 33-clip motion library + quality/runtime gates.
- `checkpoint/stable-c2-ik-joint-limits-20260914-2043` — C2 angle-limited production IK.
- `checkpoint/stable-c3-layered-animation-20260914-2048` — C3 masked additive animation layers.
- `checkpoint/stable-c4-secondary-motion-20260914-2056` — C4 production spring/secondary motion.
- `checkpoint/stable-c5-facial-mood-20260914-2101` — C5 deterministic facial/mood semantic layer + production head/neck response.

Latest rollback checkpoints include `checkpoint/pre-c3-layered-animation-20260914-2044`, `checkpoint/pre-c4-secondary-runtime-20260914-2050`, and `checkpoint/pre-c5-facial-mood-20260914-2100`.

No existing versioned rig/skin/animation contract was silently changed. Rig format remains v1; external animation content remains `krolik.animation-library/1`, format v1. IK limits, additive layers, secondary motion and facial semantic state are compatible runtime capabilities.

## Phase A

- A1 VERIFIED: real renderer-level Skeleton2D/Bone2D/Polygon2D deformation. Repeated regression remains tall `10182` changed pixels + compact `13685`, total `23867`, with evidence PNG artifacts.
- A2 BLOCKED: real DWPose/RTMPose ONNX path exists, but there is no validated `.onnx` model artifact/source in the repository. Do not invent model bytes.
- A3 VERIFIED: explicit non-destructive rig migrations.
- A4 VERIFIED on Linux/headless: real brain -> physics -> movement -> animation path with 220 live agents. Final Windows rendered 200–500-character measurement remains unverified.
- A5 VERIFIED: malformed animation data is isolated/rejected without poisoning valid clips.

## Phase B

- B1 VERIFIED: versioned external animation JSON, bounded loader/fallback and CI validation.
- B2 VERIFIED: data-driven fixtures/anchors/sockets/slots/collision/occupancy/default constraints with explicit reload.
- B3 VERIFIED: reusable pose library, semantic mirror, strength blend, animation-v1 conversion and atomic save/backup services.
- Legacy graphical authoring UI integration remains blocked because validated legacy `app.py` is missing. Do not reconstruct/guess corrupted bytes.

## Phase C — motion quality COMPLETE for currently representable runtime

### C1 authored motion library — VERIFIED
33 authored clips across idle, locomotion, turns/steps/sidestep, gestures, reactions and environment motion. Runtime proof: `KROLIK_MOTION_RUNTIME clips=33 states=10 samples=132 validation_errors=0 validation_warnings=0`.

### C2 joint-angle-limited IK — VERIFIED
Reach/stretch + interior angle limits flow through production interactions. Runtime proof: `KROLIK_IK_LIMITS far=150.000 close=25.000 custom=125.000 agent=118.000 default=175.000`.

### C3 masked additive animation — VERIFIED
Independent additive layers support weight, joint masks, root weight, phase/speed and safe base cross-fade behavior. Runtime proof: `KROLIK_LAYERED_ANIMATION base_wrist=(0.1, 0.0) masked_wrist=(0.3, 0.1) masked_ankle=(0.2, 0.0) rooted_y=2.000 switched_wrist=(0.0, 0.05) layers=0`.

### C4 production secondary motion — VERIFIED
Existing `VaultSecondaryMotion` is wired after animation/layers and before IK. Empty secondary config disables spring work. Explicitly constrained wrist/ankle endpoints remain IK-authoritative. Runtime proof: `KROLIK_SECONDARY_MOTION impulse=(-0.000462, 0.0) peak=0.000462 relaxed=0.000000 head_shift=0.000462 ik_error=0.000000 disabled=true`.

### C5 facial/mood runtime state — VERIFIED
`VaultFacialState` now consumes the existing animation-v1 `procedural_blink` and `look_at` configuration instead of introducing another incompatible contract. It provides deterministic/decorrelated blink scheduling, bounded smoothed gaze, mood presets/transitions and semantic face channels (`eye_openness`, `brow`, `mouth_curve`, `mouth_open`, gaze/blink) for future dedicated face geometry. The current single-cutout character can honestly render only head/neck posture, which is applied in production after base/additive animation and before C4 secondary motion and C2 IK. No fake eyelid/mouth deformation is claimed.

Production agent exposes mood/look target and stores the current semantic facial snapshot. The runtime regression proves deterministic blink behavior, bounded gaze, mood interpolation, actual head movement and zero interference with constrained IK.

Runtime proof: `KROLIK_FACIAL_STATE first_blink=29 decorrelated=30 peak_blink=0.985 gaze=(0.06, -0.06) mood_curve=0.440 head_shift=0.018023 ik_error=0.000000 semantic=true`.

The 220-agent stress harness now confirms facial state is active on all agents rather than merely testing one controller.

## Tests/checks actually run

No local Python/Godot execution is claimed; verification came from GitHub Actions.

C5 final commit `28924b4e918f496ccfb171b4c9440485dc9f1d31`:
- Godot Runtime CI `34878051171`: SUCCESS.
  - project parse/import PASS;
  - headless runtime smoke PASS;
  - malformed animation validation PASS;
  - 33-clip authored motion runtime PASS;
  - C3 layered animation PASS;
  - C5 facial mood state regression PASS;
  - C4 secondary motion PASS;
  - C2 IK joint-limit regression PASS;
  - rendered deformation PASS, total changed pixels `23867`, evidence upload PASS;
  - 220-agent stress PASS with `facial_active=220`, 220/220 active/moved, moved_share `1.000`, sim_fps `59.83`, avg_travel `99.59 px`, max RSS `112148 KiB` (~110 MiB), process status 0.
- Vault CI `34878051026`: SUCCESS.

C4 reference verification:
- Godot Runtime CI `34877357474`: SUCCESS, C4 metric verified and 220-agent stress ~60.08 FPS / ~109 MiB RSS.
- Vault CI `34877523944`: SUCCESS, content validator `files=3 failed=0`, core regression suite `44 passed`; backend/UI skipped because validated `app.py` is absent.

## Still blocked / unverified

- A2 real DWPose/RTMPose accuracy is blocked on a validated ONNX model artifact/source.
- Final rendered Windows FPS/CPU/memory at the intended 200–500 character scale remains unmeasured.
- Validated legacy `app.py` remains unavailable; backend/UI and direct legacy graphical editor integration remain blocked. Do not guess corrupted source bytes.
- `KROLIK_MASTER_PLAN.md` remains absent; use `docs/AUTONOMOUS_RUNBOOK.md` as the authoritative roadmap instead of inventing missing content.
- Dedicated eyelid/eye/mouth geometry is not yet present, so C5 semantic eye/mouth channels are prepared but only head/neck posture is visibly rendered today.

## Phase status

Phase A: A1/A3/A5 verified; A4 Linux/headless verified; A2 dependency-blocked; Windows rendered performance pending.

Phase B: source-independent animation/fixture/pose content pipeline verified; legacy graphical UI integration blocked on `app.py`.

Phase C: COMPLETE for current source-asset capabilities — C1 motion library, C2 IK limits, C3 layered animation, C4 secondary motion, C5 facial/mood state all verified.

## Next highest-priority unblocked task

Start Phase D with D1: eliminate drift between Python `life_sim.py` (semantic source of truth) and Godot `agent_brain.gd`.

Required vertical slice:
1. Inventory state/need/utility semantics in both Python and Godot and identify duplicated constants/thresholds/state names.
2. Define a source-independent, versioned AI policy document generated/exported from Python source-of-truth data without changing existing runtime mind snapshots.
3. Load that policy in Godot and drive `VaultAgentBrain` from it instead of hardcoded duplicate policy values where practical.
4. Preserve deterministic fallback if the policy document is missing/invalid; do not make runtime dependent on Python being installed.
5. Add Python regression proving exported policy matches `life_sim.py` semantics and Godot regression proving the production brain consumes the generated policy and reaches expected states.
6. Re-run Vault + Godot CI, then create a stable D1 checkpoint only after both are green.
