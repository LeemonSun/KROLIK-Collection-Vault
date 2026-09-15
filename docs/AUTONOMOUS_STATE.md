# AUTONOMOUS STATE

Last updated: 2026-09-15 08:33 +03:00

## Current verified engineering baseline

Latest verified engineering/code baseline before this state-only update: `27a8f20be7b34a2350a0d686775ccfc44c6549ac` (`docs: close verified A2 DWPose production baseline`).

A2 implementation itself is already green on its relevant production gates. After this state update lands and ordinary Vault CI remains green, create/preserve stable checkpoint:

`checkpoint/stable-a2-production-dwpose-20260915-0833`

No rig/skin/animation/runtime-character/AI-policy schema was bumped in A2. The portable KROLIK rig remains the existing 15-joint / 14-bone contract.

## Product path now verified

The source-independent product core now proves the continuous path:

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
-> rendered deformation evidence.

Windows also builds and executes a one-file `KROLIK_Character_Import.exe`. The packaged executable has been verified both with the deterministic/manual-correction path and with the real DWPose ONNX backend.

## A2 DWPose / RTMPose — CLOSED as verified production baseline

Detailed evidence is recorded in `docs/A2_DWPOSE_VALIDATION.md`.

### Exact model

- `dw-ll_ucoco_384.onnx`
- SHA-256 `724f4ff2439ed61afb86fb8a1951ec39c6220682803b4a8bd4f598cd913b1843`
- exact bytes `134399116`
- reproducible checksum-pinned bootstrap; model binary is not committed to Git.

### Real ONNX contract

Measured with ONNXRuntime:

- input `['batch', 3, 384, 288]`
- runtime smoke input `[1, 3, 384, 288]`
- outputs `[1, 133, 576]` and `[1, 133, 768]`
- 133 keypoints
- SimCC split ratio 2.0.

Production preprocessing now follows upstream DWPose/RTMPose behavior: BGR, bbox center/scale, fixed aspect ratio, 1.25 padding, affine warp and upstream normalization.

### Measured human ground-truth accuracy

COCO/MMPose compact fixture benchmark, run `34895056906`:

- 4 people
- 63 visible evaluated joints
- 0 failed samples
- mean normalized error `0.014758`
- median normalized error `0.010237`
- mean pixel error `5.809 px`
- PCK@0.05 `0.968254` (96.8%)
- PCK@0.10 `1.000000` (100%).

This is a compact regression baseline, not a universal fantasy/anime accuracy claim.

### Linux/Godot real product integration

DWPose Model Smoke run `34931833809`: success.

The real import/package/Godot path produced:

- backend `dwpose-onnx`
- rig score 100
- runtime-ready true
- joints 15 / bones 14
- vertices 480 / triangles 870
- weight sets 14
- collision proxies 14
- production Godot texture `563x855`
- GPU skin true
- AI policy true
- mobile state `wander`
- measured travel `41.4 px`
- rendered foreground `198410` pixels
- rendered pose difference `110381` pixels (gate minimum 1800).

Evidence artifact ID `10381279121`, ZIP SHA-256 `9beb29018ea8e59a3221ea13583bec02e93c8fbf895880a94963b6bd4c123c0e`.

### Windows packaged EXE

Windows Build run `34932156436`: success after fixing only the CI PowerShell assertion found by the previous attempt.

Windows Build run `34932467531`: success again after the explicit AI-fallback review metadata was added.

The built `KROLIK_Character_Import.exe` itself:

- loads the checksum-verified ONNX model through `KROLIK_DWPOSE_MODEL`;
- imports the upstream pose fixture without `--heuristic-rig`;
- emits `rig.backend=dwpose-onnx`;
- emits 15 joints / 14 bones;
- remains runtime-ready;
- seals and re-validates the durable package receipt.

### Stylized/anime domain coverage and safe fallback

Domain run `34932762783`: success.

Upstream DWPose anime fixtures through the actual product path:

- 4/4 produce runtime-ready packages;
- 3/4 use real `dwpose-onnx`;
- DWPose share 75%;
- unsafe silent fallbacks 0;
- explicit review fallbacks 1.

`anime1.png` is the known fallback case. Its cutout itself is high-confidence (`0.9729`), but DWPose has only 7/12 core body joints >=0.18 while production acceptance requires 8. KROLIK therefore uses the deterministic silhouette rig and sets `rig_review_required=true` instead of silently presenting it as a confidently accepted AI rig.

Follow-up domain product/Godot run `34932929973`: success after the product-slice builder was aligned with the exact production acceptance rule. It selects a real accepted DWPose anime case, seals the package and loads it through production Godot `VaultCharacterAgent`.

## Existing runtime foundation retained

Previously verified systems remain part of the baseline:

- A1 rendered real `Skeleton2D/Polygon2D` deformation;
- A3 rig migration discipline;
- A4 real 220-agent Godot stress on Linux/headless;
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
- Windows one-file headless importer.

D4/D5 life-sim expansion remains intentionally paused while the product/performance vertical path is strengthened.

## Source reconciliation / hard blocker

Canonical graphical `app.py` is still absent from Git.

Historical Git recovery candidates are not an authoritative clean replacement. The external `KROLIK_Collection_Vault_FULL_2026-09-13_2158.zip` reportedly contains the valid 13 September backend/UI source and must be reconciled if/when it becomes available in this workspace.

Rules remain:

- never synthesize or guess missing `app.py` bytes;
- core/runtime green CI does not mean graphical backend/UI is verified;
- backend/UI job remains intentionally skipped while canonical source is absent;
- full graphical product EXE publication remains blocked.

## Remaining important limitations

- Final rendered Windows 200–500-agent performance is not yet measured.
- Current 220-agent stress is useful Linux/headless regression evidence, not a Windows rendered performance promise.
- LOD/sleep/throttle tiers for 200–500 persistent characters are not yet production-complete.
- Anime/fantasy A2 QA is currently a small regression corpus, not the eventual 100–200-art Phase-F corpus.
- Busy-background matting remains conservative/review-required rather than destructive.
- Multi-person source-image UX is outside the current single-selected-character import contract.
- Final graphical manual-rig correction UX remains source-blocked with `app.py`.
- `KROLIK_MASTER_PLAN.md` is absent; `docs/AUTONOMOUS_RUNBOOK.md` remains the roadmap.

## Next highest-priority large pass

Keep D4/D5 paused for now.

Next source-independent priority is **Phase F / Windows-scale proof**, not more isolated AI features:

1. Add a real Windows Godot performance workflow that measures a rendered production-like population rather than only Linux/headless simulation. Start at 200–220 agents with deterministic workload and record wall time/FPS/RSS; if CI GPU access is unavailable, explicitly record software-render constraints rather than pretending they are target-hardware numbers.
2. Use measured profiling to implement the first production LOD/sleep/throttle tiers: full near simulation, reduced visible simulation, and far/asleep semantic simulation. Preserve behavior/snapshot compatibility and prove that sleeping agents can wake without state loss.
3. Re-run scale gates at 220 and then 300+ agents; target 500 only after the workload is honestly defined and lower tiers are stable. Do not add pooling unless profiling shows it helps.
4. Expand real-art/domain QA incrementally beyond the four upstream anime fixtures, retaining explicit review flags rather than lowering DWPose acceptance to make the percentage look better.
5. If the authoritative FULL ZIP becomes available, interrupt lower-priority work to reconcile `app.py` safely, enable backend/UI tests, and build the first complete graphical vertical slice.

## Concurrency / writer discipline

There may be multiple normal chat sessions with GitHub access. Automation cannot revoke another chat's connector permission.

For autonomous/hourly work:

- only one scheduled writer should be enabled;
- always re-read fresh `main` before every write;
- never force-push over concurrent work;
- treat 409/conflict as a signal to refetch and merge logically;
- prefer one large coherent capability block over many checkpoint-marker/micro commits;
- create real Git checkpoint branches for rollback instead of temporary marker files in the repository.
