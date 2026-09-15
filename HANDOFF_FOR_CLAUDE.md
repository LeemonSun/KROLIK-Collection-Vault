# KROLIK Collection Vault — full handoff snapshot

Snapshot date: 2026-09-15

This file is the fast handoff for another model/developer. The authoritative detailed continuity files are:

- `docs/AUTONOMOUS_RUNBOOK.md` — mission, invariants, roadmap and hourly procedure;
- `docs/AUTONOMOUS_STATE.md` — latest verified engineering state, exact runs/commits and blockers;
- `docs/A2_DWPOSE_VALIDATION.md` — DWPose/RTMPose evidence;
- `docs/TARGET_HARDWARE_BENCHMARK.md` — reproducible real-PC performance collector.

## Executive status

**Engineering/runtime core readiness: ~85%.**

**Whole final product versus the complete A–H roadmap: ~68%.**

**Estimated roadmap work remaining: ~32%.**

The project is no longer at the prototype-foundation stage. The strongest parts are import/rig/runtime deformation, animation infrastructure, three-tier population LOD, package residency/cache work, world-state persistence and regression CI. The largest unfinished blocks are the canonical graphical application/UI source, authoring UX/polish, the broad Vault content ecosystem, D4/D5 life-sim depth, 100–200-art QA expansion and final graphical Windows distribution.

Do not convert the ~68% whole-product number into a calendar-time promise. Some remaining items are broad content/UX work, and one major path is externally blocked by the missing canonical `app.py` source.

## Roadmap traffic lights

Legend:

- 🟢 = production/verified or essentially closed;
- 🟡 = substantial verified implementation exists, but the phase is not complete;
- 🔴 = major planned capability remains missing or externally blocked.

| Phase | Status | Approx. | Evidence / remaining work |
| --- | --- | ---: | --- |
| **A — Foundation** | 🟢 | **100%** | A1 rendered GPU deformation verified; A2 real DWPose integrated and measured; A3 rig migration discipline present; A4 200–500-agent stress baselines measured; A5 clip validation hardened. |
| **B — Content authoring pipeline** | 🟡 | **80%** | External data-driven animations/poses/fixtures and validators exist. Main unfinished item is the complete graphical authoring UI/workflow, currently tied to missing canonical `app.py`. |
| **C — Motion quality** | 🟢 | **95%** | 33-clip library, layered/additive animation, secondary motion and semantic facial/mood controller are present. Remaining work is mostly quality/content tuning rather than missing architecture. |
| **D — AI / life sim** | 🟡 | **60%** | D1 generated/synced AI policy, D2 personality and D3 bounded short-term memory are verified. D4 long-term affinity/favorite places and D5 character-to-character encounters/paired behaviors are intentionally paused and still unfinished. |
| **E — Vault ecosystem** | 🔴 | **30%** | Fixture/anchor infrastructure exists, but the roadmap target of 60+ categorized props/fixtures, occupancy/reservation depth and broad parameterized variants is not complete. |
| **F — Performance / QA** | 🟡 | **75%** | Full/reduced/sleep LOD, 500-agent world lifecycle, multi-art restore and F3 lazy/bounded texture residency are verified. 500 unique package identities are measured. Remaining: real target-PC run, much larger 100–200-art QA corpus, and additional pooling/streaming only if measurement justifies it. |
| **G — Visual / UX polish** | 🔴 | **20%** | Runtime foundation exists, but professional editor UX, full graphical source reconciliation and final ambience/camera/selection polish are still major work. |
| **H — Saves / distribution** | 🟡 | **60%** | Independent versioned world save/destroy/reload works at 500 characters; durable runtime/import receipts and Windows one-file importer are verified. Full graphical `KROLIK_Collection_Vault.exe`, clean-machine graphical verification and final content-pack upgrade UX remain blocked/incomplete. |

Weighted together, these phases support the current **~68% complete / ~32% remaining** estimate for the full stated product plan.

## Major verified capabilities

### 🟢 Character import and integrity

- ordinary image -> immutable original -> derived cutout;
- conservative `review_required` semantics for uncertain matting;
- versioned import/runtime-package receipts and reopen validation;
- manual normalized rig-joint correction contract;
- one-file Windows `KROLIK_Character_Import.exe` is built and executed in CI;
- originals are not destructively rewritten.

### 🟢 Real DWPose / RTMPose

Exact model:

- `dw-ll_ucoco_384.onnx`;
- SHA-256 `724f4ff2439ed61afb86fb8a1951ec39c6220682803b4a8bd4f598cd913b1843`;
- 134,399,116 bytes;
- binary is downloaded/verified and is not stored in Git.

Compact COCO ground-truth baseline:

- 4 people / 63 evaluated visible joints;
- mean normalized error `0.014758`;
- mean pixel error `5.809 px`;
- PCK@0.05 `96.8%`;
- PCK@0.10 `100%`.

Expanded provenance-pinned real/stylized QA:

- 12/12 runtime-ready;
- 10/12 accepted by real `dwpose-onnx` = 83.3%;
- CI minimum stays 75%;
- unsafe silent fallback = 0;
- `anime1.png` and `person-leaves.png` intentionally remain explicit `rig_review_required=true` fallback cases;
- accepted DWPose output is also sealed into a runtime package and loaded by production Godot.

### 🟢 Godot runtime character path

Verified continuous path includes:

- `VaultCharacterAgent`;
- `Skeleton2D/Bone2D/Polygon2D` GPU deformation;
- 15 portable KROLIK joints / 14 bones;
- skin recipe, mesh/weights and capsule collision proxies;
- authored animation, IK, layered/additive motion;
- secondary motion and facial/mood state;
- navigation/locomotion and generated AI policy;
- rendered deformation evidence rather than string-only tests.

### 🟢 Population LOD and residency

Production tiers:

- **Full** — complete GPU skin/collision/facial/secondary runtime;
- **Reduced** — AI/locomotion remain active, cheap proxy visual, detailed skin/collision suspended;
- **Sleep** — rendering/physical movement/resources released; deterministic semantic catch-up on wake.

500-agent hosted Windows LOD regression baseline:

- full 76;
- reduced 152;
- sleeping 272;
- awake moved share 1.000;
- sleeping drift 0.000;
- 11.98 FPS;
- 1105.21 MiB peak working set;
- approximately 3.5x faster than the earlier no-LOD 500-agent hosted software-render reference.

### 🟢 F3 unique-package texture residency

Old 500-unique point:

- 9.71 FPS;
- 1707.34 MiB peak;
- full textures effectively scaled with package count.

Final F3 point:

- 10.47 FPS;
- 1111.06 MiB peak;
- 96-entry bounded full-texture cache;
- 100 full decodes rather than 500;
- about 596 MiB / 34.9% peak-memory reduction;
- about 7.8% FPS improvement;
- about 80% fewer full texture decodes.

F3 is promoted to `main` and has rollback checkpoint:

`checkpoint/stable-f3-unique-package-residency-20260915`

### 🟢 World-state persistence

Verified production lifecycle:

`spawn -> runtime activity -> save -> destroy -> reload -> restore`

- 500-character scale path is green;
- brain/runtime state survives;
- multi-package identity survives;
- mixed 200-character restore returns characters to the correct original runtime package;
- scale harness was repaired so persistence validation does not waste watchdog time on irrelevant rendered frames.

### 🟢 Data-driven motion/content foundation

Already present:

- external animation JSON;
- pose/fixture data contracts;
- 33-clip motion library;
- generic animation driver direction;
- layered/additive animation;
- angle-limited IK;
- secondary motion;
- semantic facial/mood controller;
- runtime fixture/anchor infrastructure.

### 🟢 / 🟡 Target-hardware benchmark infrastructure

A new Windows collector is in the current development branch / PR #7:

`tools/run_target_hardware_benchmark.ps1`

It is designed to run the exact production workloads on the real target PC:

- no-LOD 220 / 300 / 500;
- production LOD 500;
- three repeats by default;
- median FPS and process working set;
- raw stdout/stderr and screenshots;
- Windows/CPU/RAM/GPU/driver/power-plan/Git SHA capture;
- checksum-pinned Godot 4.7.2;
- explicit rejection of software renderers as target-hardware evidence;
- JSON/CSV/Markdown reports.

The contract-only Windows CI verifies the script syntax and canonical workload without pretending GitHub-hosted software rendering is the user's GPU.

A real local run has **not yet been executed on the target RX 6650 XT**, so target-GPU FPS must remain described as unmeasured until that happens.

## Current hard blocker — 🔴 canonical graphical `app.py`

The authoritative graphical application source is still absent from Git.

An external archive named approximately:

`KROLIK_Collection_Vault_FULL_2026-09-13_2158.zip`

was reported to contain the valid September 13 backend/UI source. That source must be reconciled when available.

Rules:

- do not invent/reconstruct unknown `app.py` bytes and call them canonical;
- do not claim the graphical UI is verified because core/runtime CI is green;
- backend/UI CI remains intentionally skipped while canonical source is absent;
- do not publish a fake full graphical EXE;
- when the authoritative archive becomes available, source reconciliation should interrupt lower-priority work.

This blocker is the main reason the engineering core can be ~85% while the whole user-facing product is only ~68%.

## Current development branch / next immediate block

After the 12-case DWPose QA merge, the active work is PR #7:

`work/target-hardware-benchmark-20260915`

Purpose: reproducible target-PC benchmark collection.

Before considering the block closed:

1. keep the Windows benchmark contract green;
2. finish defensive review/fixes in the full-run PowerShell path;
3. merge PR #7 only when green;
4. create/retain a stable checkpoint;
5. update `docs/AUTONOMOUS_STATE.md`;
6. later run the collector on the actual target machine and record those real numbers.

## Highest-priority work after PR #7

Unless the canonical FULL source archive appears, continue source-independent work in roughly this order:

1. finish and merge target-hardware benchmark tooling;
2. expand provenance-known import/DWPose QA toward 100–200 diverse character arts without weakening acceptance thresholds;
3. resume D4 long-term affinity / favorite-place memory;
4. implement D5 actual character-to-character encounters / paired behaviors;
5. expand Vault props/fixtures toward the 60+ data-driven target, including occupancy/reservation and variants;
6. add pooling/offline-room/streaming only when measurement demonstrates a real bottleneck;
7. continue UX/visual polish that is independent of the missing graphical source;
8. immediately reconcile canonical `app.py` when its authoritative archive becomes accessible;
9. then enable graphical backend/UI CI, build the complete graphical vertical slice and perform clean-machine Windows verification.

## Honest remaining-work assessment

### Already behind us — 🟢

The technically risky foundation is mostly solved: import contracts, rigging, real DWPose, GPU deformation, animation architecture, AI policy/personality/memory foundation, hundreds-of-agent LOD, unique-package residency and large world-state persistence.

### Still meaningful — 🟡

The project still needs significant breadth and productization: much larger QA, deeper life-sim, a real content ecosystem, target-PC measurements, distribution polish and migration/content-pack workflows.

### Biggest gap — 🔴

The final graphical desktop product cannot be honestly called finished until canonical graphical source is restored/reconciled and the complete UI is tested/built again.

A reasonable current planning number is **~32% of the full roadmap remains**. A 24-run autonomous push can remove a meaningful part of the source-independent backlog, but it cannot by itself eliminate the missing-source blocker unless that source becomes available.

## Rules for the next model/developer

1. Read `docs/AUTONOMOUS_RUNBOOK.md` and `docs/AUTONOMOUS_STATE.md` before changing anything.
2. Inspect fresh `main` and current CI rather than trusting stale chat statements.
3. Never force-push over concurrent work.
4. Fix failing/incomplete prior work before starting a new capability.
5. One substantial capability block per autonomous pass is preferred over micro-commits.
6. Add runtime/tests/evidence; a new file by itself is not completion.
7. Do not silently change schemas.
8. Do not lower DWPose confidence/review rules merely to increase a pass percentage.
9. Keep originals immutable.
10. Keep performance and 200–500-character scaling in scope.
11. Do not fabricate target-hardware performance; execute the collector on the real machine first.
12. Do not fabricate the missing graphical application source.
