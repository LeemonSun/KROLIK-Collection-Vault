# KROLIK Autonomous Development Runbook

This file is the continuity anchor for automated hourly development passes.
Every future autonomous run MUST read `docs/PRODUCT_CONTRACT_RU.md` first, then this file, then `docs/AUTONOMOUS_STATE.md`, inspect `main`, and continue from the latest verified state instead of guessing from chat memory.

## Mission

Build KROLIK Collection Vault into a professional Windows-first local 2D/2.5D character studio + interactive dark-fantasy bestiary/Vault. The product goal is a huge visual base made of many distinct rooms where the user imports their own fictional adult character collection, places characters, assigns fixtures/constraints, leaves them there, and returns later to the same persistent world. The final user experience must install from a normal Windows installer and launch without Python/Godot/console setup.

Technical core target: drop a fictional adult character image, automatically prepare cutout/rig/skin, run it as a deformable Godot entity, allow data-driven animation, navigation, physical interaction/anchors/constraints with scene objects, autonomous life-sim behavior, and scale to hundreds of characters without destroying responsiveness. These systems are infrastructure for the Vault product, not a replacement for it.

## Non-negotiable invariants

1. Do not rewrite the project from scratch. Patch the existing architecture.
2. Python/editor/backend and Godot/runtime remain separate layers with explicit contracts.
3. Originals are immutable. All cutouts/poses/skins/previews are derived versions.
4. Do not change any versioned data contract silently. If a contract changes, increment the relevant `*_FORMAT_VERSION`/schema version and add migration + regression tests.
5. Prefer data-driven extension. New props/animations/poses/AI features should increasingly be addable through config/data rather than runtime code edits.
6. Use Godot built-ins where appropriate: Skeleton2D/Bone2D/Polygon2D, CharacterBody2D, NavigationServer2D/NavigationAgent2D, Physics2D.
7. Keep CPU mesh deformation as offline/reference tooling only; realtime deformation belongs on the Godot renderer side.
8. Never claim a test or runtime result unless actually executed or confirmed by CI.
9. Generated concept art is never called a runtime screenshot.
10. Before risky changes, create a checkpoint. After a verified substantial block, create another checkpoint/commit.
11. Never delete user collection data. Update software separately from collection/project data.
12. Keep performance in scope: target 200–500 characters through LOD, sleeping/throttled offscreen agents, efficient payloads and caching.
13. Do not let backend/AI work displace the actual Vault UX once the relevant foundation is adequate. Rooms, fixtures, persistence, graphical interaction and distribution are product-critical work.
14. Final distribution means a clean-machine Windows installer, not source files, batch files, a Python environment, or a diagnostic/importer-only executable.

## Core contracts to preserve

### Rig
`RIG_FORMAT_VERSION`; normalized `joints`; `bones`; settings. New joints require version bump + migration.

### Skin
`SKIN_FORMAT_VERSION`; vertices, triangles, bone_weights, backend, influence metadata. New custom/alpha-aware meshes must preserve field semantics or use a new backend/version.

### Animation
Clips are data: duration, loop, keyframes, joint offsets, root transforms. `animation_driver.gd` should remain generic.

### Props / fixtures
Props expose transforms, render layers, collision/occlusion profile, named anchors/sockets. Fixture constraints map body joints to named anchors. Avoid one-off hardcoded scene logic.

### Rooms / Vault
Rooms need stable IDs, types/themes, dimensions, navigation bounds, visual layers, fixture/placement slots, occupancy, adjacency and persistent state. Prefer versioned room/content-pack data so large Vault expansion does not require hardcoded runtime branches.

### Physics
Current body collision uses capsule-segment proxies. Add new collision types by extending the contract, not replacing capsules.

### AI
`life_sim.py` is the semantic source of truth. Godot brain must mirror it until an automated generation/sync path is implemented. Emotions, social outcomes and reactions to constraints should remain semantic/data-driven so personality and memory can alter the same physical situation differently.

### Distribution
Program files and user collection data are separate. App updates must preserve project data. The final installer must support a straightforward install → launch → import → use → save → reopen loop without development tools.

## Priority roadmap (Claude master-plan aligned)

Work strictly from foundation toward product. Do not jump to cosmetic breadth while core runtime remains weak, but once the core is verified do not keep polishing infrastructure while Vault-facing systems remain red.

### Phase A — Finish foundation
- A1 real Godot runtime verification on multiple character arts; visual deformation screenshots/tests, not string asserts only.
- A2 real DWPose/RTMPose ONNX model integration and measured auto-rig accuracy.
- A3 rig-format migration path for future extra joints.
- A4 real Godot stress mode with 200+ live agents and documented FPS/CPU/memory.
- A5 harden clip validation edge cases and errors.

### Phase B — Content authoring pipeline
- external animation JSON assets and auto-loader;
- animation/pose authoring UI;
- props/fixture presets moved to validated JSON + hot reload;
- reusable pose library;
- content validator in CI.

### Phase C — Motion quality
- grow animation library to 20–30+ clips;
- layered/blended animation support;
- real spring/secondary motion for hair/accessories/body regions;
- minimal facial/mood layers where source assets support them.

### Phase D — AI/life sim
- generate/sync Godot brain from Python source of truth;
- personality traits;
- short-term memory;
- long-term affinity/favorite places;
- actual character-to-character encounters and paired behaviors;
- multi-channel emotional state connected to personality, memory, social outcomes and physical constraint context.

### Phase E — Vault ecosystem
- versioned room/template library and large multi-room bestiary structure;
- 60+ categorized data-driven props/fixtures;
- occupancy/reservation;
- persistent room/fixture/character assignment;
- parameterized visual variants;
- real fixture semantics passed into runtime AI/pose/constraint systems.

### Phase F — Performance/QA
- LOD/sleeping tiers for hundreds of agents;
- pooling where measurements justify it;
- QA pipeline over 100–200 diverse character arts;
- concurrent backend/load tests.

### Phase G — visual/UX polish
- professional non-template editor/Vault UI polish;
- room/sector navigation and bestiary browsing;
- runtime ambience/light/fog/particles;
- smooth camera and selection transitions;
- base/view mode that hides technical authoring controls.

### Phase H — saves/distribution
- independent world save/checkpoint format;
- content-pack upgrades with migrations;
- persistent rooms/fixtures/constraints in saves;
- restore or finish the canonical graphical entrypoint;
- clean-machine Windows graphical EXE verification;
- produce and validate a normal Windows installer with user data outside program files.

## Current technical direction already established

The project already has meaningful work toward: cutout ensemble, DWPose backend, runtime package export, GPU Polygon2D/Skeleton2D skinning, IK, capsule collisions, navigation, keyframe pose sampling, utility brain, alpha-aware mesh experiments, checkpoint tooling, runtime prop/anchor work, secondary/floor-contact/LOD work. Inspect the actual current `main` before assuming any item is complete.

The canonical graphical `app.py` is currently absent from Git. Never fabricate its bytes or claim the historical graphical Vault is currently buildable from `main` until authoritative source is restored/reconciled. This blocker does not justify ignoring source-independent room/content/runtime/distribution work that can be built and verified honestly.

## Hourly autonomous run procedure

Every run:

1. Read `docs/PRODUCT_CONTRACT_RU.md`, this runbook, and `docs/AUTONOMOUS_STATE.md`.
2. Inspect latest `main` commit and recent CI status.
3. Check whether prior run left failing CI or an incomplete risky change. Fix that first.
4. Select ONE highest-priority unblocked substantive task from the earliest unfinished phase, while respecting the product-critical shift toward Vault rooms/fixtures/graphical UX/distribution once foundations are adequate.
5. Before a risky block, create or preserve a rollback checkpoint/branch if none exists for that block.
6. Implement the task as real code, not placeholder files or string-only tests.
7. Add/update tests that prove the task's Definition of Done as far as the available environment allows.
8. Run relevant Python tests/smokes. For Godot changes, run/verify the Godot CI or headless runtime check when available.
9. If validation fails, repair within the same run if feasible. Do not commit knowingly broken main as the final state of a run.
10. Commit the verified block to `main` with a clear message.
11. Update `docs/AUTONOMOUS_STATE.md` with:
   - timestamp/run summary;
   - exact commit SHA;
   - tests actually run + results;
   - what remains unverified;
   - next highest-priority task;
   - any blocker/dependency/model needed.
12. Keep user-visible update short: what actually changed, tests, current blocker/next step.

## Checkpoint policy

- Git commit after each coherent verified block.
- Named checkpoint branch before large/risky migrations or runtime rewrites.
- Preserve working stable branch/checkpoint instead of force-overwriting history.
- Local ZIP checkpoints are useful when the working container exists, but GitHub is the authoritative continuity source across autonomous runs.
- Never depend on `/mnt/data` surviving the next autonomous run.

## Quality bar

Do not optimize for number of commits. Optimize for verified capability. A run with one real fix is better than five placeholder modules.

A feature is not "done" because a file exists. It is done when the runtime path uses it and the relevant test/CI or actual execution verifies it.

When there is a choice between adding breadth and making one vertical path truly game-quality, choose the vertical path.

When there is a choice between more invisible infrastructure and a verified user-facing Vault capability after the required foundation already exists, prefer the Vault capability.