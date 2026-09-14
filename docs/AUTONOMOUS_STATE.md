# AUTONOMOUS STATE

Last updated: 2026-09-14 20:12 +03:00

## Current main

Latest verified implementation commit: `c9d1a23d361122a1eb5ed3d4c3924aafdb39a1cd` (`feat: make animation content external and validated`).

Verified stable checkpoints preserved in this substantial pass:
- `checkpoint/stable-nav-fallback-stress-20260914-1952` — A4 Linux/headless 220-agent movement/performance block.
- `checkpoint/stable-a1-rendered-deformation-20260914-1956` — A1 rendered Skeleton2D/Polygon2D deformation regression.
- `checkpoint/stable-a3-rig-migrations-20260914-2002` — A3 non-destructive rig migration layer + independent core Python CI.
- `checkpoint/stable-a5-animation-validation-20260914-2006` — A5 runtime malformed-animation isolation/validation.
- `checkpoint/stable-b1-external-animation-content-20260914-2011` — first Phase B vertical slice: external validated animation library integrated into runtime package export.

Relevant rollback checkpoints are also preserved, including `checkpoint/pre-nav-fallback-20260914-1948`, `checkpoint/pre-a1-rendered-deformation-20260914-1954`, `checkpoint/pre-a3-rig-migrations-20260914-2000`, `checkpoint/pre-a5-animation-validation-20260914-2003`, and `checkpoint/pre-b1-external-animation-content-20260914-2008`.

No existing versioned rig/skin/animation format was silently changed. Rig format remains v1 and animation format remains v1.

## What changed in this substantial pass

### A4 production locomotion/stress failure repaired and verified
`VaultCharacterAgent` navigation now falls back to its direct target when `NavigationAgent2D` has no usable path/region rather than accepting a near-current waypoint and silently stalling. Navigation targets are synchronized only when the target actually changes. This fixed the real production movement path rather than weakening the benchmark.

Godot Runtime CI verified 220/220 live agents moving, 100% crossing the >=8 px threshold, ~99.59 px average travel, ~60 simulated physics FPS over 180 sample frames and ~107-108 MiB maximum RSS, well below the 512 MiB CI budget.

### A1 real rendered deformation proof completed
Commit `130ef950be42acc59d90cc398146374f2d03492a` added a renderer-level regression for the actual `VaultSkinnedCharacter` path using `Skeleton2D`, `Bone2D`, `Polygon2D`, real mesh triangles and bone weights. It renders two procedural character proportions under Xvfb/llvmpipe, captures baseline/posed PNG frames and requires material pixel differences.

Verified evidence from Godot Runtime CI:
- tall 128x256 case: 16810 foreground pixels, 10182 changed pixels (threshold 491);
- compact 192x192 case: 18788 foreground pixels, 13685 changed pixels (threshold 552);
- total changed pixels: 23867;
- four PNG evidence files uploaded by CI.

### A2 inspected and dependency-blocked, not faked
`rig_tools.py` already contains the real local DWPose/RTMPose WholeBody ONNX inference path and Windows provider preference including DirectML. `requirements-ai.txt` contains ONNX Runtime dependencies. The repository recursive tree contains no `.onnx` model artifact, therefore real-model accuracy measurement cannot be completed safely yet. No model binary was invented or silently downloaded.

### A3 non-destructive rig migration path completed
`rig_migrations.py` now provides explicit versioned migration infrastructure independent of the missing legacy editor source. It migrates versionless/pre-v1 records and direct legacy joint maps, handles JSON database rows, preserves unknown/custom future joints/bones/metadata, is idempotent on current v1 records and refuses destructive downgrade of newer formats. Six migration regressions were added. `RIG_FORMAT_VERSION` remains 1 because no v1 semantics were changed.

Vault CI was split so source-independent foundation code runs even while `app.py` is unavailable. The repaired core job initially verified 20 tests green.

### A5 animation runtime validation completed
Commit `cea941f7dca655b6cd1f9768646bcbc839df9293` hardened the real Godot `VaultAnimationDriver` without changing animation format v1. It rejects/isolates malformed data clips, validates finite positive duration, keyframe structure, timestamps/range/order, finite joint offsets, root transform values/scales, missing state clip references and invalid blends while retaining the legacy procedural fallback for old packages with no data clips.

`animation_validation_harness.gd` executes the real driver against malformed content. Verified metric:
`KROLIK_ANIMATION_VALIDATION valid_clips=1 errors=6 warnings=3 default=good head_half=(0.1000,-0.0500)`.

Godot Runtime CI `34872535957` completed SUCCESS. In the same run A1 remained green and A4 remained green: 220/220 moved, moved_share=1.000, avg_travel=99.59 px, sim_fps=60.25, RSS=109676 KiB (~108 MiB).

### Phase B started: external animation content + loader + validator
Commit `c9d1a23d361122a1eb5ed3d4c3924aafdb39a1cd` moved the default animation library out of Python hardcoded clip definitions into `content/animations/default_v1.json` while preserving the existing animation v1 document semantics.

Added `animation_content.py` with bounded validation and loading:
- explicit `krolik.animation-library/1` schema and format v1 validation;
- limits for file size, clip/state/keyframe/joint counts;
- finite numeric/root/joint checks and state->clip reference validation;
- local user override through `KROLIK_ANIMATION_LIBRARY`;
- invalid override falls back non-destructively to the bundled validated library and reports the reason;
- fresh deep-copied documents prevent one export/caller from mutating future exports.

`runtime_package.build_manifest()` now embeds a fresh validated animation document from the external JSON asset. Existing `DEFAULT_ANIMATION_GRAPH` / `DEFAULT_POSE_CLIPS` import names are retained for compatibility but are populated from the external library rather than being the source of truth.

Added `tools/validate_content.py` and wired it into the independent core CI. `tests/test_animation_content.py` proves bundled-library validity, runtime-package integration, independent manifest copies, adding a custom clip/state without runtime code changes, invalid override fallback and malformed-content rejection.

## Tests/checks actually run

No local Python or Godot executable was available through this connector-only environment, so no local test execution is claimed.

Verified through GitHub Actions:
- Godot Runtime CI `34872535957` for A5 commit `cea941f7dca655b6cd1f9768646bcbc839df9293`: SUCCESS; animation validation PASS; rendered deformation PASS; 220-agent stress PASS; deformation evidence uploaded.
- Vault CI `34872535923` for the same A5 commit: SUCCESS.
- Vault CI `34872999767` for Phase B commit `c9d1a23d361122a1eb5ed3d4c3924aafdb39a1cd`: SUCCESS; source-integrity PASS; core syntax PASS; content validator PASS (`files=1 failed=0`); core regression suite PASS with `26 passed`; backend/UI SKIPPED because validated `app.py` remains absent.
- Godot Runtime CI `34872999503` for the same Phase B commit: SUCCESS; project import PASS; headless runtime smoke PASS; A5 animation validation PASS; A1 rendered deformation PASS; evidence upload PASS; A4 220-agent stress PASS.

## Still unverified / incomplete

- A2 real DWPose/RTMPose model accuracy remains blocked by absence of a validated ONNX model artifact/source.
- A4 rendered Windows FPS/CPU/memory remains unmeasured. Linux/headless 220-agent performance is verified but is not a substitute for the final Windows rendered target.
- Validated legacy Python/editor `app.py` is still unavailable, so backend/UI/scale tests and direct integration into the old professional editor UI cannot be executed without guessing missing source bytes.
- `KROLIK_MASTER_PLAN.md` is still absent. Continue using the priority/phase order in `docs/AUTONOMOUS_RUNBOOK.md` rather than inventing missing roadmap text.

## Phase status

Phase A foundation is complete for all currently unblocked Linux/connector-verifiable work:
- A1: verified;
- A2: blocked on external validated ONNX model artifact;
- A3: verified;
- A4: Linux/headless verified; Windows rendered measurement remains;
- A5: verified.

Phase B has started. External animation JSON + auto-loader and the first content-validator path are verified.

## Next highest-priority unblocked task

Continue Phase B with the general-purpose props/fixtures/interaction content layer while the legacy UI source and ONNX model remain blocked:
1. Inventory current prop/fixture/anchor/constraint code and preserve existing contracts.
2. Move reusable prop/fixture presets into versioned validated JSON rather than hardcoded runtime definitions.
3. Define named sockets/anchors, render/occlusion layer, collision profile, occupancy/capacity and supported constraint targets as data, not one-off scenes.
4. Add safe loader/cache + explicit reload path suitable for future editor hot reload.
5. Extend `tools/validate_content.py` and source-independent CI regressions for these assets.
6. Prove at least one exported/runtime interaction uses the data asset rather than merely checking file/string existence.

After that, continue Phase B with reusable pose-library assets and authoring services; the graphical animation/pose authoring UI remains dependent on recovery of the validated editor source unless a clean independent authoring surface is intentionally introduced later.
