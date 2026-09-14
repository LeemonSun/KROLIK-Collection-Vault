# AUTONOMOUS STATE

Last updated: 2026-09-14 20:49 +03:00

## Current verified implementation

Latest verified implementation commit: `4ab7274fbd404ace559283a58806d9dc3aac6887` (`test: gate layered animation runtime behavior`).

This state update is documentation-only; use the latest `main` head for the next implementation parent, while `4ab7274f...` is the exact C3 code/workflow commit verified by both CI workflows.

Verified stable checkpoints currently preserved:
- `checkpoint/stable-nav-fallback-stress-20260914-1952` — A4 Linux/headless 220-agent movement/performance block.
- `checkpoint/stable-a1-rendered-deformation-20260914-1956` — A1 rendered Skeleton2D/Polygon2D deformation regression.
- `checkpoint/stable-a3-rig-migrations-20260914-2002` — A3 non-destructive rig migration layer.
- `checkpoint/stable-a5-animation-validation-20260914-2006` — A5 malformed-animation isolation/validation.
- `checkpoint/stable-b1-external-animation-content-20260914-2011` — B1 external validated animation content.
- `checkpoint/stable-b2-fixture-content-20260914-2020` — B2 data-driven reusable fixtures/anchors/slots/constraints.
- `checkpoint/stable-b3-pose-library-20260914-2024` — B3 reusable pose library and authoring services.
- `checkpoint/stable-c1-motion-library-20260914-2028` — C1 expanded motion library + Godot execution proof.
- `checkpoint/stable-c2-ik-joint-limits-20260914-2043` — C2 joint-angle-limited IK through the production agent path.
- `checkpoint/stable-c3-layered-animation-20260914-2048` — C3 masked additive animation layers.

Relevant rollback checkpoints include `checkpoint/pre-b3-pose-library-20260914-2022`, `checkpoint/pre-c1-motion-library-20260914-2025`, `checkpoint/pre-c2-joint-limits-20260914-2029`, and `checkpoint/pre-c3-layered-animation-20260914-2044` in addition to earlier Phase A/B rollback points.

No existing versioned rig/skin/animation contract was silently changed. Rig format remains v1 and animation content remains `krolik.animation-library/1`, format v1. C2 constraint angle fields and C3 additive layers are optional runtime capabilities layered on top of existing contracts.

## Completed foundation / authoring work

### Phase A — currently unblocked foundation work verified

A1 real GPU deformation is renderer-verified through `VaultSkinnedCharacter` using `Skeleton2D`, `Bone2D`, `Polygon2D`, mesh triangles and bone weights. The Xvfb/llvmpipe regression renders two body proportions and requires real changed pixels. Current repeated metric remains:
- tall 128x256: 10182 changed pixels;
- compact 192x192: 13685 changed pixels;
- total: `23867` changed pixels;
- four evidence PNGs uploaded on each successful Godot Runtime CI run.

A2 real local DWPose/RTMPose inference code and DirectML-preferred Windows provider path exist, but real-model accuracy remains dependency-blocked because the repository has no validated `.onnx` model artifact/source. No model bytes were invented or silently substituted.

A3 explicit non-destructive rig migration infrastructure is verified. It preserves unknown/custom metadata, is idempotent for current v1 records, migrates supported older layouts and refuses unsafe downgrade of newer formats.

A4 Linux/headless live-agent performance remains verified with the real brain -> physics -> movement -> animation path. Current C3 run still reports 220/220 active and moved, 100% moved share, ~99.59 px average travel, ~60.11 simulated FPS and ~108 MiB RSS against a 512 MiB budget. Final Windows rendered performance remains unmeasured.

A5 `VaultAnimationDriver` rejects malformed clips/keyframes/root/joint values without poisoning valid clips and retains deterministic legacy fallback. The malformed-content harness remains green.

### Phase B — source-independent authoring/content pipeline verified

B1 moved animation content out of hardcoded Python into versioned `content/animations/default_v1.json`, added bounded loading/fallback and integrated fresh validated documents into runtime package export. `tools/validate_content.py` gates authored assets in CI.

B2 moved reusable fixture behavior into `content/fixtures/default_v1.json`. The catalog supports reusable fixture kinds such as frames/cages/barrels/chain/rope anchors and accessory mounts with named anchors/sockets, slots, render/occlusion data, collision profiles, occupancy/capacity and default constraint targets. `FixtureCatalog` provides cached loading and explicit reload; `interaction_runtime.py` resolves real constraints/targets through the catalog rather than a one-off scene table.

B3 added versioned `content/poses/default_v1.json` plus `pose_content.py` authoring services. Poses can be filtered, semantically mirrored left/right, blended onto rigs with strength, converted into the existing animation-v1 clip/state representation, and saved atomically with backup behavior. No runtime schema bump was required.

The graphical legacy editor UI remains blocked by the missing validated `app.py`; the source-independent authoring/content layer is intentionally usable without guessing those bytes.

## Phase C motion-quality progress

### C1 — expanded authored motion library verified

The external motion library now contains 33 clips rather than the original 7, covering idle variants, locomotion variants, turns/steps/sidesteps, gestures, reactions and environment-specific motion. `motion_quality.py` rejects fake-static authored motions, broken loop continuity, insufficient family coverage and unreasonable offsets.

The Godot end-to-end motion harness copies and loads the actual external JSON and executes every clip through the production `VaultAnimationDriver`. Verified metric:
`KROLIK_MOTION_RUNTIME clips=33 states=10 samples=132 validation_errors=0 validation_warnings=0`.

### C2 — joint-angle-limited IK verified

`VaultIKSolver` now supports interior angle limits in addition to reach/stretch limits. Default elbow/knee bounds prevent pathological straight locking/folding, optional user-authored `min_joint_deg`, `max_joint_deg`, and `max_stretch` flow through `interaction_runtime.py` into `VaultCharacterAgent`, and fractional constraint strength preserves segment lengths rather than lerping solved bone positions into stretched geometry.

`ik_limit_harness.gd` exercises both the low-level solver and the real CharacterAgent animation -> interaction IK path. The harness also frees its test-only agent cleanly before exit. Verified metric:
`KROLIK_IK_LIMITS far=150.000 close=25.000 custom=125.000 agent=118.000 default=175.000`.

### C3 — masked additive/layered animation verified

`VaultAnimationDriver` now supports runtime additive layers without changing animation-v1 content format:
- independent clip/phase/playback speed per layer;
- weight 0..1;
- optional joint masks, suitable for upper-body gestures over locomotion;
- separate `root_weight` so overlays do not disturb locomotion root unless explicitly requested;
- deterministic sorted layer application;
- invalid layer clips are rejected non-destructively;
- base cross-fade source is captured before overlays, preventing the active overlay from being baked and applied twice when the base animation changes.

`layered_animation_harness.gd` verifies masking, weighted joint addition, root isolation/weighting, active-layer weight updates, invalid clip rejection without mutation, independent layer phase/speed, base-animation switching without double application, and clear-to-base behavior.

Verified metric:
`KROLIK_LAYERED_ANIMATION base_wrist=(0.1, 0.0) masked_wrist=(0.3, 0.1) masked_ankle=(0.2, 0.0) rooted_y=2.000 switched_wrist=(0.0, 0.05) layers=0`.

## Tests/checks actually run

No local Python or Godot execution is claimed; this pass used the connected private GitHub repository and verified execution through GitHub Actions.

Latest coherent C3 verification for commit `4ab7274fbd404ace559283a58806d9dc3aac6887`:
- Vault CI `34876857206`: SUCCESS.
  - source-integrity: PASS;
  - core Python syntax: PASS;
  - content validation: PASS (`files=3 failed=0` for animations, fixtures, poses);
  - core regression suite: PASS, `44 passed`;
  - backend/UI: SKIPPED because validated `app.py` is still absent.
- Godot Runtime CI `34876857171`: SUCCESS.
  - verified Godot 4.7.2 download/hash: PASS;
  - project parse/import: PASS;
  - headless runtime smoke: PASS;
  - malformed animation validation regression: PASS;
  - authored 33-clip motion runtime regression: PASS;
  - C3 layered animation regression: PASS;
  - C2 IK joint limit regression: PASS;
  - rendered Skeleton2D/Polygon2D deformation: PASS, total changed pixels `23867`;
  - deformation evidence artifact upload: PASS;
  - 220 live-agent stress: PASS, 220/220 moved, moved_share=1.000, sim_fps=60.11, avg_travel=99.59 px, max RSS `110412 KiB` (~108 MiB), process status 0.

C2 clean verification immediately before C3:
- Vault CI `34876363130`: SUCCESS.
- Godot Runtime CI `34876363134`: SUCCESS with `KROLIK_IK_LIMITS far=150.000 close=25.000 custom=125.000 agent=118.000 default=175.000`; no test-only RID/ObjectDB leak warnings after harness cleanup.

C1 final end-to-end verification:
- Godot Runtime CI `34874875805`: SUCCESS; all 33 external clips/10 states/132 samples executed through Godot, A1/A4 regressions remained green.
- Vault CI `34874875885`: SUCCESS.

B3 Vault CI `34874058867`: SUCCESS; content validation included animations/fixtures/poses and the then-current core suite passed.
B2 Vault CI `34873673376`: SUCCESS; fixture content validation and regressions passed.

## Still blocked / unverified

- A2 real DWPose/RTMPose accuracy is blocked by absence of a validated ONNX model artifact/source.
- Final rendered Windows FPS/CPU/memory at the intended 200–500 character scale remains unmeasured. Linux/headless 220-agent performance is verified but is not a substitute.
- Validated legacy Python/editor `app.py` is still unavailable. Do not reconstruct or guess corrupted/missing source bytes. Backend/UI/scale jobs correctly remain skipped while source integrity is absent.
- `KROLIK_MASTER_PLAN.md` is still absent from repository search as of this update. Continue following `docs/AUTONOMOUS_RUNBOOK.md`; do not invent roadmap text.
- Graphical pose/animation authoring integration into the legacy editor remains blocked on `app.py`, although the independent data/services layer is functional and CI-gated.

## Phase status

Phase A:
- A1 verified;
- A2 blocked on validated ONNX artifact;
- A3 verified;
- A4 Linux/headless verified; Windows rendered measurement remains;
- A5 verified.

Phase B:
- B1 external animation content/loader/validator verified;
- B2 reusable fixture/anchor/constraint content + reloadable catalog verified;
- B3 reusable pose library + source-independent authoring services verified;
- legacy graphical authoring UI integration blocked on validated `app.py`.

Phase C:
- C1 33-clip authored motion library + quality gates verified;
- C2 joint-angle-limited interaction IK verified;
- C3 masked additive/layered animation verified;
- next unblocked item is C4 production secondary/spring motion integration.

## Next highest-priority unblocked task

C4 should integrate the existing `VaultSecondaryMotion` solver into the actual production character pipeline rather than writing a duplicate spring module.

Required vertical slice:
1. Inspect runtime manifest/physics data already exported for secondary channels and preserve existing formats.
2. Give `VaultCharacterAgent` a `VaultSecondaryMotion` instance and configure/reset it from existing manifest secondary-motion data when present.
3. Apply secondary joint offsets after sampled base + additive animation and before interaction IK, so IK remains authoritative for constrained wrists/ankles while unconstrained hair/head/shoulders/hips/accessory channels retain inertial lag.
4. Keep the feature zero-cost or near-zero when no secondary channels are configured; do not force spring work across all 200–500 agents.
5. Add a deterministic Godot runtime harness proving acceleration produces lag, offsets stay bounded, damping returns toward rest, and the production CharacterAgent path applies secondary motion before IK without breaking C2 limits.
6. Add the harness as a required Godot Runtime CI step and rerun the complete C1/C2/C3/A1/A4 suite.
7. Only after green CI create a stable C4 checkpoint and update this state again with exact final SHA/run IDs.
