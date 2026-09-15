# AUTONOMOUS STATE

Last updated: 2026-09-15 08:10 +02:00

## Current verified engineering baseline

Latest verified engineering/code baseline before this state-only update:

`fb7e4261e9fb9c8b4c8ee37e57cf6f0515c6b534` (`ci: lock in measured Windows LOD performance floor`).

This baseline has green evidence from:

- Windows Godot LOD Scale run `34935517813`;
- Vault CI run `34935517863`;
- Godot Runtime CI run `34935292690` on the same runtime LOD implementation before the workflow-only performance-floor commit.

No rig/skin/animation/runtime-character/AI-policy schema was bumped. The portable KROLIK rig remains the existing 15-joint / 14-bone contract.

## Product path verified

The source-independent product core proves the continuous path:

ordinary image
-> immutable original
-> derived/reviewable cutout
-> real DWPose auto-rig when accepted OR explicit review-required heuristic fallback
-> optional manual joint corrections
-> skin recipe
-> collision proxies
-> versioned runtime manifest
-> durable import/runtime-package receipts
-> safe package reopen validation
-> production `VaultCharacterAgent`
-> GPU `Skeleton2D/Polygon2D` skin
-> authored animation/layers/facial/secondary motion
-> IK/physics/navigation/AI
-> rendered deformation evidence
-> distance-based full/reduced/sleep population LOD.

Windows also builds and executes a one-file `KROLIK_Character_Import.exe`. The packaged executable has been verified both with deterministic/manual-correction import and with the real DWPose ONNX backend.

## A2 DWPose / RTMPose — CLOSED

Detailed evidence remains in `docs/A2_DWPOSE_VALIDATION.md`.

Exact production model:

- `dw-ll_ucoco_384.onnx`
- SHA-256 `724f4ff2439ed61afb86fb8a1951ec39c6220682803b4a8bd4f598cd913b1843`
- bytes `134399116`
- model binary is checksum-pinned and not committed to Git.

Measured compact human ground-truth baseline:

- 4 people / 63 visible evaluated joints;
- mean normalized error `0.014758`;
- median normalized error `0.010237`;
- mean pixel error `5.809 px`;
- PCK@0.05 `96.8%`;
- PCK@0.10 `100%`.

Stylized/anime regression corpus:

- 4/4 runtime-ready packages;
- 3/4 accepted by real `dwpose-onnx`;
- known `anime1.png` fallback remains explicitly `rig_review_required=true` rather than silently accepted.

This is a compact regression baseline, not a universal anime/fantasy accuracy claim.

## A4 Windows rendered scale — CLOSED as measured baseline

Workflow: `.github/workflows/windows-godot-scale.yml`.

Reference run `34933824299` used Windows Server 2025, Godot 4.7.2 and the same production `VaultCharacterAgent` path with runtime manifest, GPU skin, AI policy, personality, memory, facial state and actual locomotion.

Renderer was:

`ANGLE / Microsoft Basic Render Driver`

This is a GitHub-hosted software-render baseline, **not** target RX 6650 XT hardware and not a promise of target-machine FPS.

Measured no-LOD population:

| Agents | FPS | Peak working set | Movement / visuals |
| ---: | ---: | ---: | --- |
| 220 | 6.96 | 603.45 MiB | 220/220 moved, 220/220 visual |
| 300 | 6.12 | 775.41 MiB | 300/300 moved, 300/300 visual |
| 500 | 3.42 | 1172.12 MiB | 500/500 moved, 500/500 visual |

This proves that the upper 500-character target executes on Windows with the production runtime path before LOD; the low FPS reflects the hosted software renderer.

Stable pre-LOD checkpoint already preserved:

`checkpoint/stable-a4-windows-rendered-500-20260915-0844`

## Phase F population LOD / sleep — FIRST PRODUCTION TIER CLOSED

New production component:

`VaultPopulationLOD`

Three explicit tiers are implemented without changing the full-detail character contract:

### Full

- ordinary `VaultCharacterAgent` behavior remains unchanged;
- GPU deformable skin, IK/collision proxies, facial and secondary motion stay live.

### Reduced

- AI and locomotion remain live;
- detailed GPU skin pose updates are suspended;
- a cheap flat visual proxy remains visible and follows the root character motion;
- detailed collision proxy updates / collision participation are suspended;
- procedural face and secondary motion are suspended.

### Sleep

- rendering is hidden;
- physical movement and collision participation stop;
- the LOD manager accumulates deterministic simulation `delta`, not wall-clock time;
- on wake the semantic brain catches up in one bounded step so needs and short-term memory continue aging;
- full or reduced visual/physics state is restored without recreating the character contract.

`VaultCollisionRig` now supports explicit enable/disable so reduced/sleep tiers can suspend detailed capsule proxy updates safely.

### Sleep/wake continuity proof

Windows LOD runs `34935337605` and `34935517813` both pass the real production-package continuity regression.

Representative marker:

`KROLIK_POPULATION_LOD status=ok registered=1 full=1 reduced=0 sleeping=0 reduced_travel=25.4 caught_up=0.3 memory_age_before=0.383 memory_age_after=0.683 sleep_drift=0.0 wake_travel=42.73 gpu_skin_restored=true collision_restored=true`

The regression verifies:

- full -> reduced;
- reduced character remains visible and keeps moving;
- reduced GPU deformable skin / detailed collision / procedural detail are suspended;
- reduced -> sleep;
- sleeping character has zero physical drift;
- semantic time is accumulated while asleep;
- short-term memory ages while asleep;
- sleep -> full wake restores the original GPU skin, collision rig and controller flags;
- locomotion resumes after wake.

## 500-agent rendered LOD performance

Dedicated workflow:

`.github/workflows/windows-godot-lod-scale.yml`

### First measured green run

Run `34935337605`:

- agents: 500;
- full: 76;
- reduced: 152;
- sleeping: 272;
- awake: 228;
- awake moved: 228/228;
- sleeping max physical drift: `0.000`;
- 120 sample frames in `9.6674 s`;
- `12.41 FPS`;
- peak working set `1108.38 MiB`;
- screenshot evidence `1028x720`, sampled foreground `21494`;
- renderer: Microsoft Basic Render Driver via ANGLE.

Compared with the no-LOD 500-agent reference (`3.42 FPS`, `1172.12 MiB`), this is about `3.63x` higher measured FPS and about `5.4%` lower peak working set on the hosted software renderer.

### Locked performance-floor rerun

Run `34935517813` on commit `fb7e4261e9fb9c8b4c8ee37e57cf6f0515c6b534`:

- continuity regression: success;
- full: 76;
- reduced: 152;
- sleeping: 272;
- awake moved share: `1.000`;
- sleeping max drift: `0.000`;
- `11.98 FPS`;
- peak working set `1105.21 MiB`;
- measured speedup recorded by workflow: `3.5x` vs the 3.42 FPS reference;
- process exit 0;
- rendered screenshot evidence present.

Permanent CI floor now rejects regressions below:

- `8.0 FPS` on this exact hosted-Windows workload;
- `1.5 GiB` peak working set.

Artifact from the locked rerun:

- ID `10382608361`;
- name `windows-godot-lod-scale-500`;
- SHA-256 `46e3ddd333258abaddbcf29eb88afb44d75a52b942b1077949c9966a679b1672`.

The benchmark repeats one production runtime package across the population. It proves runtime/LOD scaling behavior; it does **not** claim the memory footprint of 500 unique high-resolution character textures.

## Existing runtime foundation retained

Previously verified systems remain part of the baseline:

- A1 rendered real `Skeleton2D/Polygon2D` deformation;
- A2 real DWPose product integration;
- A3 rig migration discipline;
- A4 Windows rendered population scaling through 500 agents;
- A5 animation clip validation;
- data-driven animations/poses/fixtures;
- 33-clip motion library;
- angle-limited IK;
- layered/additive animation;
- secondary motion;
- semantic facial/mood controller;
- D1 generated Python -> Godot AI policy;
- D2 personality traits with cached hot-path biases;
- D3 bounded short-term memory;
- durable source/import/package integrity checks;
- real-image import QA matrix;
- manual rig-joint override contract;
- rendered imported-character evidence;
- Windows one-file headless importer;
- Phase-F full/reduced/sleep population LOD with Windows 500-agent regression gate.

D4/D5 life-sim expansion remains intentionally paused while source-independent product/performance/QA work is completed.

## Source reconciliation / hard blocker

Canonical graphical `app.py` is still absent from Git.

Historical Git recovery candidates are not an authoritative clean replacement. The external `KROLIK_Collection_Vault_FULL_2026-09-13_2158.zip` reportedly contains the valid 13 September backend/UI source and must be reconciled if/when it becomes available in this workspace.

Rules remain:

- never synthesize or guess missing `app.py` bytes;
- core/runtime green CI does not mean graphical backend/UI is verified;
- backend/UI job remains intentionally skipped while canonical source is absent;
- full graphical product EXE publication remains blocked.

## Remaining important limitations

- Hosted Windows performance uses Microsoft Basic Render Driver; target RX 6650 XT performance still requires a real target-hardware run.
- Current 500-agent rendered benchmark repeats one runtime character package and therefore is not a 500-unique-art memory test.
- Anime/fantasy A2 QA is still a small regression corpus rather than the eventual 100–200-art Phase-F corpus.
- Busy-background matting remains conservative/review-required rather than destructive.
- Multi-person source-image UX is outside the current single-selected-character import contract.
- Final graphical manual-rig correction UX remains source-blocked with `app.py`.
- D4 long-term affinity / D5 encounter expansion remains paused, not deleted.
- `KROLIK_MASTER_PLAN.md` is absent; `docs/AUTONOMOUS_RUNBOOK.md` remains the roadmap.

## Next highest-priority large pass

Keep D4/D5 paused unless the product/performance path stops yielding useful work.

Next source-independent priority is **Phase F real-art diversity + production QA**:

1. Inventory currently available real/stylized character fixtures and build an explicit corpus manifest rather than inventing assets.
2. Expand import -> rig -> skin -> package -> Godot QA beyond the current four-anime regression set, preserving review-required semantics instead of lowering DWPose acceptance thresholds.
3. Add a multi-art rendered runtime stress mode using genuinely distinct existing assets where available; record unique-texture memory separately from repeated-package population performance.
4. Add target-hardware benchmark instructions/collector for the user's RX 6650 XT so the same 220/300/500 workloads can later be compared honestly against hosted software-render results.
5. Only add further pooling/caching/LOD complexity when profiling of the multi-art or target-hardware workload shows a concrete bottleneck.
6. If the authoritative FULL ZIP becomes available, interrupt lower-priority work to reconcile `app.py` safely, enable backend/UI tests and build the first complete graphical vertical slice.

## Concurrency / writer discipline

Multiple normal chat sessions may still have GitHub access. Always re-read fresh `main` before every write and never force-push over concurrent work.

Current user instruction: scheduled/hourly writer remains disabled. Do **not** re-enable it unless the user explicitly asks later.

For manual development:

- fresh-read `main` before each write;
- treat 409/conflict as a signal to refetch and merge logically;
- prefer one large coherent capability block over checkpoint-marker/micro commits;
- create real Git checkpoint branches for rollback instead of temporary marker files.
