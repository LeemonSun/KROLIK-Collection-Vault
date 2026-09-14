# AUTONOMOUS STATE

Last updated: 2026-09-14 20:02 +03:00

## Current main

Latest verified implementation/CI commit: `7e7041bb893c60b0875e26927b6e0b626f28da5b` (`ci: run core regressions independently from missing app source`).

Verified stable checkpoints preserved this pass:
- `checkpoint/stable-nav-fallback-stress-20260914-1952` — A4 Linux/headless 220-agent movement/performance block.
- `checkpoint/stable-a1-rendered-deformation-20260914-1956` — A1 rendered Skeleton2D/Polygon2D deformation regression.
- `checkpoint/stable-a3-rig-migrations-20260914-2002` — A3 non-destructive rig migration layer + independent core Python CI.
Rollback before A3: `checkpoint/pre-a3-rig-migrations-20260914-2000`.

## What changed in this substantial pass

### A4 runtime movement/stress repaired
Production `VaultCharacterAgent` navigation now falls back to direct locomotion when `NavigationAgent2D` has no usable path instead of replacing a valid direct target with a near-current waypoint. This closed the real runtime `moved=0` failure rather than weakening the benchmark. Godot Runtime CI verified 220/220 agents moving, 100% crossing the 8 px travel threshold, about 99.59 px average travel, ~59.97 physics FPS over the 180-frame sample, and ~107 MiB maximum RSS. The stress requirements remain 220 agents, >=80% moved >=8 px, <=20 s sample wall time and <=512 MiB RSS.

### A1 real renderer deformation proof completed
Commit `130ef950be42acc59d90cc398146374f2d03492a` added a rendered GPU deformation regression for real Godot `Skeleton2D` + `Polygon2D` skinning. Godot Runtime CI run `34871604299` completed SUCCESS, including project import/runtime checks and the rendered regression. PNG evidence is uploaded by CI. This is renderer evidence, not a string/node-existence assertion.

### A2 inspected and dependency-blocked, not faked
`rig_tools.py` already contains a real local DWPose/RTMPose WholeBody ONNX inference path with provider preference including DirectML on Windows, COCO/WholeBody mapping and deterministic heuristic/MediaPipe fallback. `requirements-ai.txt` contains ONNX Runtime dependencies. However the repository contains no `.onnx` model artifact, so measured real-model auto-rig accuracy cannot be completed safely in this environment without a validated model artifact/source. No model binary was invented or silently downloaded. Continue other unblocked foundation work while this dependency is absent.

### A3 non-destructive rig migration path completed
Commit `cc73a3da6a8f7f69bd3bf5a69b611308e23a2364` added `rig_migrations.py` and regression coverage. The migration API handles versionless/pre-v1 storage, direct legacy joint maps, JSON database records, idempotent current-version reads, malformed contracts and refusal to destructively downgrade newer rigs. Unknown/custom joints, bones and metadata are preserved so future finger/face/accessory/cloth roots are not silently discarded. `RIG_FORMAT_VERSION` remains 1: no contract semantics were changed, so no artificial version bump was made.

The first independent core-CI attempt exposed that `tests/test_scale.py` imports missing legacy `app.py`; that test correctly belongs behind the source-integrity gate. Commit `7e7041bb893c60b0875e26927b6e0b626f28da5b` removed it from the source-independent core set and explicitly sets `PYTHONPATH=.`. Vault CI run `34872203634` then verified both Core module syntax PASS and Core regression suite PASS. Backend/UI remains intentionally skipped because validated `app.py` is absent.

## Tests/checks actually run

No local Python or Godot executable was available through this connector-only environment; no local execution is claimed.

Verified through GitHub Actions:
- Godot Runtime CI for production navigation fallback: PASS; 220/220 agents moved, moved share 100%, avg travel ~99.59 px, ~59.97 physics FPS, RSS ~107 MiB.
- Godot Runtime CI `34871604299` for A1 rendered deformation commit `130ef950be42acc59d90cc398146374f2d03492a`: SUCCESS.
- Vault CI `34872203634` for `7e7041bb893c60b0875e26927b6e0b626f28da5b`: source-integrity PASS, core module syntax PASS, core regression suite PASS, backend/UI SKIPPED because `app.py` is absent.
- Earlier Vault CI `34872113546` for the initial A3 commit failed only in the newly introduced core-python job; this was repaired by `7e7041bb...` and the superseding run is green at the job level.

## Still unverified / incomplete

- A2 real DWPose/RTMPose model accuracy is blocked by absence of a validated ONNX model artifact in the repository/environment.
- A4 rendered Windows FPS/CPU/memory is still unmeasured; Linux/headless stress is verified and healthy but is not a substitute for the Windows rendered target.
- Legacy Python/editor `app.py` remains unavailable; backend/UI/scale tests that import it cannot be executed without guessing missing source bytes.
- `KROLIK_MASTER_PLAN.md` remains absent; use phase ordering in `docs/AUTONOMOUS_RUNBOOK.md` rather than inventing it.

## Next highest-priority task

Phase A5 is now the highest-priority unblocked foundation task: harden animation clip validation edge cases/errors while preserving animation format v1 semantics. Add a source-independent validator and regression tests for malformed duration/loop/keyframes, non-monotonic or out-of-range time, invalid/unknown joint offsets, invalid root transforms, non-finite numbers and excessive payloads. Wire validation into the runtime-package/content path without requiring missing `app.py`. After A5 is verified, Phase A is functionally complete except the explicitly blocked A2 real-model measurement and Windows-rendered A4 measurement; proceed into Phase B external animation JSON assets/auto-loader and validated data-driven authoring.
