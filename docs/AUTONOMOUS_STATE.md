# AUTONOMOUS STATE

Last updated: 2026-09-14 20:58 +03:00

## Current verified implementation

Latest verified code/test commit: `b49a2d024d751dfc9f39bb3aec08de4a0ff1b426` (`test: assert animation secondary IK pipeline ordering`).

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

Latest rollback checkpoints include `checkpoint/pre-c2-joint-limits-20260914-2029`, `checkpoint/pre-c3-layered-animation-20260914-2044`, and `checkpoint/pre-c4-secondary-runtime-20260914-2050`.

No existing versioned rig/skin/animation contract was silently changed. Rig format remains v1; external animation content remains `krolik.animation-library/1`, format v1. New IK limits, additive layers and secondary motion are compatible optional runtime capabilities.

## Phase A

- A1 VERIFIED: real `VaultSkinnedCharacter` deformation through Skeleton2D/Bone2D/Polygon2D. Current repeated rendered regression: tall changed pixels `10182`, compact `13685`, total `23867`; evidence PNGs uploaded by Godot CI.
- A2 BLOCKED: real DWPose/RTMPose local ONNX path exists, but repository has no validated `.onnx` model artifact/source. Do not invent model bytes.
- A3 VERIFIED: explicit non-destructive rig migrations, preservation of unknown/custom data, idempotence and downgrade refusal.
- A4 VERIFIED on Linux/headless: real brain -> physics -> movement -> animation path with 220 live agents. Windows rendered 200–500-character measurement still unverified.
- A5 VERIFIED: malformed clip/keyframe/root/joint data is isolated/rejected without poisoning valid animation data.

## Phase B

- B1 VERIFIED: default animation library moved to versioned `content/animations/default_v1.json`; bounded loader/fallback and CI content validation.
- B2 VERIFIED: `content/fixtures/default_v1.json` drives reusable fixtures, anchors/sockets, slots, render/occlusion metadata, collision profile, occupancy/capacity and default constraints; explicit catalog reload exists; runtime constraints resolve through content data.
- B3 VERIFIED: `content/poses/default_v1.json` + `pose_content.py` provide reusable poses, filters, semantic left/right mirroring, strength blending, conversion to animation-v1 and atomic save/backup.
- Legacy graphical authoring UI remains blocked because validated legacy `app.py` is missing. Do not reconstruct/guess corrupted bytes.

## Phase C

### C1 — authored motion library

VERIFIED. External motion library now has 33 clips covering idle, locomotion, turns/steps/sidestep, gestures, reactions and environment-specific motion. `motion_quality.py` rejects fake-static clips, bad loop continuity, insufficient family coverage and unreasonable offsets.

Godot proof: `KROLIK_MOTION_RUNTIME clips=33 states=10 samples=132 validation_errors=0 validation_warnings=0`.

### C2 — joint-angle-limited IK

VERIFIED. `VaultIKSolver` supports reach/stretch and interior joint-angle limits. Optional `min_joint_deg`, `max_joint_deg`, `max_stretch` flow from interaction payload into `VaultCharacterAgent`. Fractional strength preserves segment lengths.

Godot proof: `KROLIK_IK_LIMITS far=150.000 close=25.000 custom=125.000 agent=118.000 default=175.000`.

### C3 — masked additive animation

VERIFIED. `VaultAnimationDriver` supports independent additive layers with clip/phase/speed, weight, joint mask, optional root weight, deterministic order, non-destructive invalid-clip rejection, and correct base cross-fade behavior without double application.

Godot proof: `KROLIK_LAYERED_ANIMATION base_wrist=(0.1, 0.0) masked_wrist=(0.3, 0.1) masked_ankle=(0.2, 0.0) rooted_y=2.000 switched_wrist=(0.0, 0.05) layers=0`.

### C4 — production secondary/spring motion

VERIFIED. Existing `VaultSecondaryMotion` is now connected to `VaultCharacterAgent` rather than remaining a disconnected helper.

Implementation behavior:
- `load_runtime_manifest()` consumes existing `physics.secondary`; no manifest schema bump.
- empty secondary config disables the path and resets solver state, avoiding spring work for characters without configured channels;
- sampled base + C3 additive animation is assembled first;
- secondary offsets are applied next;
- interaction IK is applied last and remains authoritative for explicitly constrained wrist/ankle endpoints;
- C3 layer wrapper methods are exposed on CharacterAgent for runtime callers.

Godot runtime harness proves acceleration lag, max-offset bounding, damping toward rest, real CharacterAgent head motion, constrained wrist authority, and zero-work disabled path.

Godot proof: `KROLIK_SECONDARY_MOTION impulse=(-0.000462, 0.0) peak=0.000462 relaxed=0.000000 head_shift=0.000462 ik_error=0.000000 disabled=true`.

The source-level Python regression was strengthened to assert the actual production ordering `animation -> secondary motion -> IK`, rather than matching the obsolete `_apply_animation_pose(sample)` call signature.

## Tests/checks actually run

No local Python/Godot execution is claimed; verification came from GitHub Actions.

C4 production/runtime commit `9fbcc2ce959b8b1d8dbefd0b8844f5f6ce2ec4c9`:
- Godot Runtime CI `34877357474`: SUCCESS.
- project parse/import PASS; headless smoke PASS.
- malformed animation regression PASS.
- 33-clip authored motion regression PASS.
- C3 layered animation regression PASS.
- C4 secondary motion production regression PASS.
- C2 IK joint-limit regression PASS.
- rendered deformation PASS with total changed pixels `23867`; evidence upload PASS.
- 220-agent stress PASS: 220/220 active/moved, moved_share `1.000`, sim_fps `60.08`, avg_travel `99.59 px`, max RSS `111000 KiB` (~109 MiB), process status 0.

Final C4 test-fix commit `b49a2d024d751dfc9f39bb3aec08de4a0ff1b426`:
- Vault CI `34877523944`: SUCCESS.
- source-integrity PASS.
- core syntax PASS.
- content validator PASS (`files=3 failed=0`).
- core regression suite PASS: `44 passed`.
- backend/UI SKIPPED because validated `app.py` remains absent.

Recent C3 verification:
- Vault CI `34876857206`: SUCCESS, 44 passed.
- Godot Runtime CI `34876857171`: SUCCESS, all C1/C2/C3/A1/A4 gates green.

## Still blocked / unverified

- A2 real DWPose/RTMPose accuracy: blocked on a validated ONNX model artifact/source.
- Final rendered Windows FPS/CPU/memory at intended 200–500 character scale remains unmeasured.
- Validated legacy `app.py` is unavailable; backend/UI and direct legacy editor integration remain blocked. Do not guess/rebuild corrupted source bytes.
- `KROLIK_MASTER_PLAN.md` is still absent from repository search; follow `docs/AUTONOMOUS_RUNBOOK.md` rather than inventing missing roadmap content.

## Next highest-priority unblocked task

Continue Phase C with C5 facial/mood runtime layers, but do not fake visual facial deformation that the current single-cutout rig cannot represent.

Required approach:
1. Inventory existing `procedural_blink` / `look_at` animation content and any runtime face-capable joints/channels.
2. Add a deterministic face/mood state layer that can expose blink/look target/mood parameters independently of body locomotion, while using actual head/neck joint offsets where the current rig can honestly render them.
3. Keep facial state optional and near-zero-cost when disabled/unconfigured.
4. If there is no deformable eye/mouth geometry yet, represent eye/mouth controls as runtime semantic channels for future face mesh/sprite layers rather than pretending a whole-body PNG can visibly blink.
5. Add Godot regression proving deterministic blink scheduling, bounded look-at/head response, mood transitions, and no interference with C3/C4/C2 ordering.
6. Re-run complete Godot and Vault CI; only create stable C5 checkpoint after green.
