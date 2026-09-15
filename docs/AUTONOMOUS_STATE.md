# AUTONOMOUS STATE

Last updated: 2026-09-15

## Current verified engineering baseline

F3 unique-package residency is now promoted to `main`.

Current F3 promotion SHA:

`48adbb963a41312ca1984cae4a3f7275f0deef73` (`ci: make world-state scale harness frame-free`).

Stable rollback branch:

`checkpoint/stable-f3-unique-package-residency-20260915`

Latest fully verified production-code SHA before cleanup/state/harness-only commits:

`f292ab6082fbae9aa14a54a53a4a81c7bd6ee3b8` (`fix: preserve lazy package cache GDScript nesting`).

All five relevant production regressions are green on this production SHA:

- Windows Godot LOD Scale run `34943207027` — success;
- Godot World State Scale run `34943207122` — success;
- Windows Multi-Art LOD Scale run `34943207023` — success;
- Godot Multi-Art World State run `34943207059` — success;
- Windows Unique-Package Scale run `34943207141` — success.

The final F3 PR world-state regression is also green on promoted head `48adbb963a41312ca1984cae4a3f7275f0deef73`:

- Godot World State Scale PR run `34944917660` — success.

That last harness change removes expensive SceneTree frame waits from the persistence-only scale regression. The production runtime behavior/schema was not changed by it. The temporary lazy-texture patch workflow used during development was removed before promotion and is not part of the intended product/CI architecture.

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
-> distance-based full/reduced/sleep population LOD
-> versioned world-state save/destroy/reload
-> multi-package identity-preserving restore.

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

Stable pre-LOD checkpoint:

`checkpoint/stable-a4-windows-rendered-500-20260915-0844`

## Phase F population LOD / sleep — PRODUCTION TIER CLOSED

Production component: `VaultPopulationLOD`.

Three explicit tiers are implemented without changing the full-detail character contract.

### Full

- ordinary `VaultCharacterAgent` behavior remains unchanged;
- GPU deformable skin, IK/collision proxies, facial and secondary motion stay live.

### Reduced

- AI and locomotion remain live;
- detailed GPU skin pose updates are suspended;
- a cheap flat visual proxy remains visible and follows root motion;
- detailed collision participation is suspended;
- procedural face and secondary motion are suspended.

### Sleep

- rendering is hidden;
- physical movement and collision participation stop;
- deterministic simulation delta is accumulated instead of wall-clock time;
- the semantic brain catches up on wake;
- full/reduced runtime state is reconstructable from the sealed runtime package.

Windows run `34943207027` re-verifies the production full -> reduced -> sleep -> wake path on the final F3 runtime cache implementation. GPU skin, collision and locomotion restore correctly after wake.

## 500-agent rendered LOD performance

Dedicated workflow: `.github/workflows/windows-godot-lod-scale.yml`.

Earlier locked hosted-Windows baseline run `34935517813`:

- full: 76;
- reduced: 152;
- sleeping: 272;
- awake moved share: `1.000`;
- sleeping max drift: `0.000`;
- `11.98 FPS`;
- peak working set `1105.21 MiB`;
- measured speedup `3.5x` vs the 3.42 FPS no-LOD reference.

Permanent CI floor remains:

- minimum `8.0 FPS` on this exact hosted-Windows workload;
- maximum `1.5 GiB` peak working set.

The hosted runner uses Microsoft Basic Render Driver via ANGLE. These metrics prove regression behavior, not expected RX 6650 XT performance.

## H2 world-state persistence — CLOSED

The production runtime has a verified large-population lifecycle:

spawn -> runtime activity -> save -> destroy -> reload -> restore.

The 500-character workflow is green on final F3 production code. Character brain/runtime state and package identity survive the lifecycle.

Stable H2 checkpoint:

`checkpoint/stable-h2-world-state-scale-20260915-1010`

The final F3 PR exposed an old harness-only timing problem: the regression printed `status=ok` but could then be killed by the 180-second external watchdog while spending time on irrelevant SceneTree frames/cleanup. Commit `48adbb963a41312ca1984cae4a3f7275f0deef73` makes the persistence harness frame-free and the PR run `34944917660` completes successfully without changing production persistence semantics.

## F2 multi-art runtime + persistence — CLOSED

A four-art checksum-pinned QA corpus is imported into separately sealed runtime packages and exercised through the production Godot runtime.

Windows multi-art 500-agent measurement before F3 cache specialization:

- 500 production agents;
- 4 distinct sealed runtime packages/textures;
- about `10.48 FPS`;
- about `572 MiB` peak working set;
- all three LOD tiers populated;
- all awake agents move;
- sleeping agents remain physically stable.

Mixed world-state persistence is verified with 200 characters across four package identities:

- save size about `0.290 MiB`;
- spawn about `654 ms`;
- save about `18.7 ms`;
- load about `10 ms`;
- restore about `817 ms`;
- each restored character returns to its original runtime manifest/package rather than an arbitrary cache entry.

Final F3 regression run `34943207059` confirms mixed-package save/reload still succeeds after lazy texture residency changes.

Stable F2 checkpoint:

`checkpoint/stable-f2-multi-art-scale-20260915-1017`

## F3 unique-package residency — CLOSED AND PROMOTED

### Problem measured

A dedicated QA fan-out tool creates hundreds of independently sealed package paths from the four verified template packages. This isolates package/texture uniqueness from ordinary repeated-character population cost.

Initial Windows unique-package curve with the old always-decode cache:

| Unique packages | Agents | FPS | Peak working set |
| ---: | ---: | ---: | ---: |
| 32 | 500 | 7.35 | 640.73 MiB |
| 128 | 500 | 9.79 | 876.16 MiB |
| 500 | 500 | 9.71 | 1707.34 MiB |

The runtime remained CPU/render viable, but peak memory scaled badly because every package request decoded and pinned a full-resolution `Texture2D`, including reduced/sleeping characters.

### Production fix

`VaultRuntimePackageCache` separates cheap package metadata residency from full decoded texture residency:

- manifest/image metadata stays cached for all seen packages;
- `load_package(manifest_path, include_texture)` supports metadata-only loads;
- `VaultCharacterAgent.load_runtime_manifest(..., build_runtime_resources=false)` no longer decodes or retains a full character texture;
- reduced LOD can build its small proxy directly from the immutable image file;
- sleeping LOD holds no full texture;
- waking/full LOD rehydrates the full immutable texture on demand;
- decoded full textures are protected by a bounded LRU cache;
- default full-texture cache limit is `96` entries;
- active agents remain safe after cache eviction because they retain their own RefCounted texture reference;
- cache metrics expose metadata entries, decoded texture entries, limit, parses, decodes and evictions.

No runtime-package schema changed.

### Final measured unique-package curve

Windows Unique-Package Scale run `34943207141`, artifact `windows-unique-package-scale` ID `10385483863`, artifact SHA-256 `b8ed9af2aa7e7943ffc2ab596b88c5bf390459d46daa70a5dd5dc277aa82c603`:

| Unique packages | Full textures cached | Full decodes | FPS | Peak working set |
| ---: | ---: | ---: | ---: | ---: |
| 32 | 22 | 22 | 8.60 | 629.02 MiB |
| 128 | 83 | 83 | 10.69 | 804.20 MiB |
| 500 | 96 | 100 | 10.47 | 1111.06 MiB |

At the hardest 500-unique point versus the old implementation:

- peak working set: `1707.34 -> 1111.06 MiB`;
- memory saved: `596.28 MiB`, about `34.9%`;
- FPS: `9.71 -> 10.47`, about `7.8%` improvement;
- full texture decodes: `500 -> 100`, an `80%` reduction;
- resident full-texture cache is bounded at `96` rather than 500.

LOD shape in the final 500-unique run:

- full: 76;
- reduced: 161;
- sleeping: 263;
- resident: 76;
- proxy: 161;
- released: 263;
- awake moved share: `1.000`;
- sleeping physical drift: `0.000`.

This closes the concrete 500-unique RAM bottleneck found by profiling.

### Offline-room / unloaded-cell tier decision

A more aggressive fourth tier where a closed room/cell fully unloads its character remains a valid future optimization, especially for collections materially larger than the current 200–500 target.

It is intentionally **not** required for the current 500-character target after F3: the measured 500-unique workload is green at about 1.11 GiB peak on the hosted software-render Windows runner. Add the offline-room tier only when a >500/1000+ exploratory workload or target-machine profiling demonstrates a new concrete residency bottleneck.

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
- Phase-F full/reduced/sleep population LOD;
- H2 500-character world-state save/destroy/reload;
- F2 mixed-art runtime and identity-preserving persistence;
- F3 bounded/lazy unique-package texture residency.

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
- F3 uses 500 independent sealed package/cache identities built from four checksum-pinned source artworks; it validates package uniqueness and residency scaling, not 500 genuinely different artistic source images.
- Anime/fantasy A2 QA is still a small regression corpus rather than the eventual 100–200-art Phase-F corpus.
- Busy-background matting remains conservative/review-required rather than destructive.
- Multi-person source-image UX is outside the current single-selected-character import contract.
- Final graphical manual-rig correction UX remains source-blocked with `app.py`.
- D4 long-term affinity / D5 encounter expansion remains paused, not deleted.
- `KROLIK_MASTER_PLAN.md` is absent; `docs/AUTONOMOUS_RUNBOOK.md` remains the roadmap.

## Next highest-priority large pass

Keep D4/D5 paused unless the product/performance path stops yielding useful work.

F3 promotion is complete. Next source-independent priorities are now:

1. Expand real/stylized import QA beyond the current four-art regression corpus using only accessible, provenance-known fixtures; keep explicit review-required semantics rather than lowering DWPose acceptance thresholds.
2. Add target-hardware benchmark instructions/collector so the same 220/300/500 workloads can be run on the user's RX 6650 XT and compared honestly with hosted software-render metrics.
3. Add further pooling/offline-room/streaming complexity only if >500 exploratory or real target-hardware profiling identifies a concrete bottleneck.
4. If the authoritative FULL ZIP becomes available, interrupt lower-priority work to reconcile `app.py` safely, enable backend/UI tests and build the first complete graphical vertical slice.

## Concurrency / writer discipline

Multiple normal chat sessions may still have GitHub access. Always re-read fresh `main` before every write and never force-push over concurrent work.

Current user instruction: scheduled/hourly writer remains disabled. Do **not** re-enable it unless the user explicitly asks later.

For manual development:

- fresh-read `main` before each write;
- treat 409/conflict as a signal to refetch and merge logically;
- prefer one large coherent capability block over checkpoint-marker/micro commits;
- create real Git checkpoint branches for rollback instead of temporary marker files.
