# AUTONOMOUS STATE

Last updated: 2026-09-14 23:27 +03:00

## Current repository state

Current verified `main`: `6de69e371b1fa6fba9db372739e484eec279c0f9` (`ci: capture rendered imported-character evidence`).

Stable checkpoint: `checkpoint/stable-import-render-proof-20260914-2327` at `6de69e371b1fa6fba9db372739e484eec279c0f9`.

Previous coherent import/reopen Windows block at `54cc1c8ff9a0d90365a277481c5961e7119384a9` is also verified: Vault CI and Windows Build both concluded success.

No rig/skin/animation/runtime-character/AI-policy schema was changed in this block.

## Verified vertical path now available

The source-independent core now proves this continuous path:

ordinary image -> immutable original -> derived cutout -> heuristic/manual-correctable rig -> skin recipe -> runtime package -> durable import/package receipts -> production `VaultCharacterAgent` -> GPU `Skeleton2D/Polygon2D` skin -> animation/IK/physics/AI -> safe reopen validation.

The Windows one-file headless importer is built and executed in CI, including manual joint correction and durable package reopen validation.

## New in this run — rendered imported-character evidence

Added `runtime_godot/scripts/imported_character_render_harness.gd` and wired it into Godot Runtime CI.

This regression does NOT create a procedural checker texture or synthetic 2-bone rig. Python first imports the ordinary-image fixture through the real `character_import.py` path and writes the same production runtime package used by the headless vertical slice. Godot then loads that exact package through `VaultCharacterAgent`, requires the production GPU skin (no flat fallback), renders the imported character at rest, applies a visible pose through `VaultSkinnedCharacter`, renders again, and requires a material pixel difference.

PNG evidence is uploaded as `imported-character-render-evidence` (`imported_baseline.png`, `imported_posed.png`).

Verified metric from Godot Runtime CI run `34892777728`:

- character=`ci_core_slice`
- packaged texture=`256x512`
- skin vertices=`264`
- skin bones=`14`
- rig joints=`15`
- rig bones=`14`
- rendered foreground pixels=`41971`
- changed pixels after pose=`8687`
- required minimum=`1800`
- `gpu_skin=true`
- `evidence=true`
- renderer=`gl_compatibility`

Artifact ID: `10368100305`.

The same run also reconfirmed:

- production ordinary-image headless runtime: joints=15, bones=14, weights=14, collisions=14, GPU skin=true, policy=true, state=wander, travel=41.4 px;
- import QA matrix: 4/4 cases passed, one manually corrected rig, GPU skin/collisions/policy all true;
- 33-clip motion runtime: 132 samples, 0 validation errors/warnings;
- layered animation, facial state, secondary motion and IK regressions pass;
- procedural rendered deformation baseline remains green: 23867 changed pixels total;
- 220-agent stress: 220/220 active and moved, moved_share=1.000, avg_travel=99.59 px, 44.26 simulated FPS on this runner, max RSS 121304 KiB (~119 MiB), process status 0.

Vault CI run `34892777545` for the same SHA is green for canonical-source audit, durable import/package reopen smoke and the full core regression suite. Backend/UI remains intentionally skipped because canonical `app.py` is absent.

## Source reconciliation / blockers

- Canonical graphical `app.py` is still absent from Git. Historical in-repo recovery candidates are not a clean authoritative replacement. Never synthesize/guess the missing source. Reconcile the external `KROLIK_Collection_Vault_FULL_2026-09-13_2158.zip` when it becomes available in this workspace.
- Backend/UI therefore remains source-blocked and unverified.
- A2 real DWPose/RTMPose quality is still incomplete. The existing ONNX backend is real, but no validated model artifact + measured accuracy corpus has yet been committed/verified.
- Final rendered Windows 200–500-agent performance remains unmeasured.
- Busy-background matting remains conservative/review-required rather than destructive.
- `KROLIK_MASTER_PLAN.md` is absent; `docs/AUTONOMOUS_RUNBOOK.md` is the authoritative roadmap.

## Next highest-priority task

Keep D4/D5 paused while the end-to-end product path is still being strengthened.

Next source-independent priority is A2 enablement plus real-asset QA:

1. add a reproducible, checksum-pinned DWPose model bootstrap for `dw-ll_ucoco_384.onnx` without committing the 134 MB binary to Git;
2. verify the actual model session/input/output contract against `rig_tools.py` and add a real-model smoke path that can be run explicitly/manual CI without slowing every normal push;
3. build a small measured pose-quality corpus before claiming A2 complete;
4. continue expanding import/render evidence from deterministic fixtures toward user-provided real art when an appropriate asset is available without committing user art unintentionally.
