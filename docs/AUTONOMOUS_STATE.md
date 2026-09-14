# AUTONOMOUS STATE

Last updated: 2026-09-14 22:30 +03:00

## Current repository state

Current verified `main` head: `418777447eeeb2300c02b6b7e70b3bfe2d3ed7e3` (`ci: execute Python-to-Godot core vertical slice`).

Current verified runtime feature baseline still includes D3 short-term memory from `a64a66388c7bb467bf79275ed2609820fc69a89d`; the newer main adds source-readiness hardening plus a verified source-independent image→rig→skin→manifest→Godot core vertical slice without changing production data schemas.

Stable checkpoints relevant to current work:
- `checkpoint/stable-d1-ai-policy-sync-20260914-2113` — generated/versioned Python→Godot AI policy sync.
- `checkpoint/stable-d2-personality-traits-20260914-2122` and later D2 checkpoint — backward-compatible personality traits + optimized runtime bias cache.
- `checkpoint/stable-d3-short-term-memory-20260914-2136` — bounded short-term memory runtime.
- `checkpoint/stable-d3-source-readiness-20260914-2222` — verified D3 baseline plus explicit canonical-source readiness audit.
- `checkpoint/stable-core-vertical-slice-20260914-2230` — verified Python→runtime-package→production Godot character vertical slice.

No rig/skin/animation format contract changed in this reconciliation/vertical-slice block. AI policy remains `krolik.ai-policy/1`, format version 1. Runtime character schema remains `krolik.runtime-character/1`.

## Critical source-of-truth correction

A full external project snapshot named `KROLIK_Collection_Vault_FULL_2026-09-13_2158.zip` is known from an independent review to have contained a healthy, substantial `app.py` backend. That exact external ZIP is not currently available to this GitHub connector/session.

The current Git repository does **not** contain a canonical `app.py`, and exhaustive in-repository recovery checks prove that the historical mirrors are not safe authoritative replacements:

- `tools/source_restore.zip`: present but not a valid ZIP; SHA-256 `1a3a8ec920980f842b3032a875a71bf2dd6d9d5807d77a85829ff8ab6b6da869`.
- canonical `tools/source_restore_parts/part_00..part_10.b64`: incomplete because the canonical set is missing.
- historical original `part_07` combination: invalid base64 transport.
- historical corrected `part_07` combination: decodes to a valid ZIP containing `app.py`, but `archive.testzip()` reports CRC failure specifically for `app.py`; payload SHA-256 `057cacf29919636b0ec66ed82ea9fa16dd524fd928d68cb9b6df5c49f715bfdc`.
- legacy `.source_sync` chunks: not a valid ZIP; SHA-256 `948dcb40911ff5687b8c7f28efe39f9a6beea31fc7f9c0a7c66a979a55e7c180`.

Therefore **do not reconstruct, guess, patch, or synthesize `app.py` bytes from the damaged in-Git recovery artifacts**.

`tools/audit_source_readiness.py` is the canonical non-destructive source-readiness check. It reports `present`, `recoverable`, or `blocked` and never writes restored files.

Current machine result:
`KROLIK_SOURCE_READINESS status=blocked app_present=false recoverable=false`

Vault CI emits `FULL PRODUCT SOURCE BLOCKED` when `app.py` is absent. Core/runtime CI may still be green, but backend/UI is explicitly **not counted as verified**.

The durable recovery/reconciliation procedure is documented in `docs/SOURCE_RECONCILIATION.md`.

## Source recovery experiments preserved

Two isolated recovery branches were created only for investigation; neither is authoritative and neither should be merged:

1. `recovery/authoritative-source-20260913`
   - reconstruction run `34885802331`;
   - text-safe historical source payload reconstructed to 123335 bytes;
   - failure: `archive.testzip() -> corrupt archive member: app.py`.

2. `recovery/binary-source-20260913`
   - run `34885864801`;
   - historical `tools/source_restore.zip` was 8650 bytes;
   - failure: `zipfile.BadZipFile: File is not a zip file`.

Old checkpoint trees and the commit that introduced backend/UI CI were also inspected. They already expected `app.py`, but `app.py` was not a normal tracked file in those Git trees. No successful `Restore complete stable source tree` commit exists in repository history.

Conclusion: the healthy backend seen in the external FULL ZIP existed outside the successfully preserved Git source tree and was lost/corrupted during the attempted mirror/recovery transport.

## Phase status

- Phase A: A1/A3/A5 VERIFIED; A4 Linux/headless VERIFIED; A2 blocked on validated DWPose/RTMPose ONNX model; rendered Windows 200–500-agent measurement pending.
- Phase B: external animation/fixture/pose content pipeline VERIFIED. Graphical backend/UI source is explicitly SOURCE-BLOCKED until the authoritative FULL ZIP is reconciled.
- Phase C: VERIFIED for current source-asset capabilities: 33-clip motion library, angle-limited IK, additive layers, production secondary motion, semantic facial/mood state.
- Phase D: D1 VERIFIED; D2 VERIFIED; D3 short-term memory VERIFIED. D4 long-term affinity exists as unverified work on a recovery branch and is PAUSED while source reconciliation / product vertical-slice work has higher priority.
- Product integration: a **headless core vertical slice is now VERIFIED** across Python and Godot. It is intentionally not called a full user-facing vertical slice because cutout UI, canonical backend/UI, real DWPose model, save/reload UX, and Windows packaging remain incomplete.

## D1 — generated AI policy sync VERIFIED

`life_sim.py` remains the semantic/tuning source of truth. `ai_policy.py` validates it and `tools/export_ai_policy.py` reproducibly verifies both committed copies:
- `content/ai/default_policy_v1.json`;
- `runtime_godot/data/ai_policy_v1.json`.

Godot proof:
`KROLIK_AI_POLICY schema=krolik.ai-policy/1 source=harness-custom default_state=social overridden_state=idle energy_after_rate=0.600 production_state=social production_loaded=true`.

## D2 — personality traits VERIFIED

Five bounded neutral-at-0.5 traits remain verified:
- curiosity;
- sociability;
- boldness;
- patience;
- resilience.

Production proof:
`KROLIK_PERSONALITY legacy_neutral=true curious=inspect sociable=social bold=wander patient=idle production=social traits=5`.

The original nested dictionary hot path caused ~31.90 FPS at 220 agents; cached per-state trait biases recovered that stress class without weakening correctness gates.

## D3 — bounded short-term memory VERIFIED

D3 is complete for the current architecture and must not be rebuilt by future autonomous runs.

Semantics:
- compact bounded per-agent memory entries;
- event kind + optional subject;
- valence, importance, age, TTL;
- deterministic dedup/update;
- deterministic expiry/eviction;
- maximum capacity controlled by generated AI policy (current default 8);
- focused-subject utility bias with capped influence;
- empty memory preserves legacy behavior;
- cached aggregate memory bias avoids rebuilding nested event effects on every physics tick.

Godot runtime proof:
`KROLIK_MEMORY capacity=8 dedupe=true expired=true legacy=idle unfocused=idle focused=social hard_gate=contained production_entries=1 production_state=social`

D3 Godot Runtime CI `34881517303`: SUCCESS.
- rendered deformation: tall changed pixels `10182`, compact `13685`, total `23867`;
- stress: 220/220 moved, moved_share `1.000`, avg_travel `99.59 px`, 180 frames in `2.9201 s`, simulated `61.64 FPS`, max RSS `121552 KiB` (~119 MiB), process status 0.

D3 Vault CI `34881517299`: SUCCESS for core checks at that revision with 60 tests; backend/UI was skipped because canonical `app.py` was absent.

## Canonical source-readiness hardening VERIFIED

Commit chain ending at `5173c7f690a5d9b3ef550f16e179714bd602f2e1` added:
- `tools/audit_source_readiness.py` — read-only source/recovery audit;
- `tests/test_source_readiness.py` — regression coverage for present/recoverable/blocked cases and no-write behavior;
- explicit `canonical-source-readiness` CI job;
- explicit `FULL PRODUCT SOURCE BLOCKED` warning and job summary when `app.py` is absent;
- backend/UI conditional on actual canonical source presence.

Vault CI `34886425415`: SUCCESS for the audit/core pipeline.
- source audit correctly reported BLOCKED;
- AI policy sync `targets=2 status=clean`;
- content validation `files=4 failed=0`;
- core regression suite 64 tests PASS;
- backend/UI SKIPPED and explicitly not counted as verified.

## Headless core vertical slice VERIFIED

Current stable vertical-slice commit: `418777447eeeb2300c02b6b7e70b3bfe2d3ed7e3`.

Purpose: prove one continuous source-independent integration path through the existing architecture instead of only testing isolated modules.

The deterministic CI path is:

`RGBA test image` → `rig_tools.detect_rig(prefer_ai=False)` → heuristic silhouette rig → `runtime_package.build_manifest()` → GPU skin recipe + collision proxies + animation/mind data → `runtime_package.write_package()` → generated `manifest.json + character.png` → production `VaultCharacterAgent.load_runtime_manifest()` → GPU `VaultSkinnedCharacter` → brain/animation/physics → real movement on Godot physics frames.

This fixture is explicitly a deterministic integration-test image, not generated concept art and not a substitute for validating arbitrary user art.

Python package proof from Vault/Godot CI:
`KROLIK_CORE_VERTICAL_SLICE character_id=ci_core_slice backend=heuristic-silhouette rig_score=100.0 runtime_ready=True joints=15 bones=14 vertices=264 triangles=462 bone_weights=14 collision_proxies=14`

Production Godot proof:
`KROLIK_CORE_VERTICAL_SLICE_GODOT character=ci_core_slice joints=15 bones=14 weights=14 collisions=14 gpu_skin=true policy=true state=wander phase=0.583 travel=41.4`

This proves on one integrated fixture that:
- source image is read by the current Python rig pipeline;
- portable rig has all 15 current joints and 14 bones;
- skinning recipe contains 264 vertices, 462 triangles and 14 bone-weight channels;
- 14 collision proxies survive export/import;
- runtime manifest schema is consumed by production Godot code;
- Godot builds the GPU skinned visual instead of flat fallback;
- generated AI policy remains active;
- production physics callback runs;
- agent reaches a mobile state and moves 41.4 px during the harness;
- animation/IK joint pipeline preserves the complete joint set.

Vault CI `34887064659`: SUCCESS.
- syntax PASS;
- AI policy sync PASS;
- content validation `files=4 failed=0`;
- explicit vertical-slice package build PASS;
- core regression suite PASS: 65 tests;
- canonical source audit still correctly reports BLOCKED;
- backend/UI SKIPPED and not counted as product verification.

Godot Runtime CI `34887064711`: SUCCESS.
- verified Godot 4.7.2 download/hash + project import/headless smoke PASS;
- Python-generated runtime package build PASS;
- production Python→Godot vertical-slice harness PASS;
- AI policy, personality, D3 memory, animation validation, 33-clip library, layered animation, facial state, secondary motion and IK limits PASS;
- rendered deformation PASS: `23867` changed pixels total and evidence artifact uploaded;
- 220-agent stress PASS: agents/active/facial/policy/personality/memory all `220`, moved `220/220`, moved_share `1.000`, avg_travel `99.59 px`, sample `180` frames / `4.1393 s` / `43.49 FPS`, max RSS `121520 KiB` (~119 MiB), process status 0.

The final stress number is a separate GitHub runner sample and should not be interpreted as a production-code regression versus the earlier ~61.64 FPS sample; the vertical-slice block adds test/build integration and does not add per-agent production hot-path logic. Cross-run Linux CI FPS remains a regression signal, not a final Windows performance claim.

## D4 — long-term affinity work PAUSED / UNVERIFIED

Preserved work branch:
`work/d4-long-term-affinity-recovery-20260914`

Current head:
`08ff0c113f268a775265f387adba1c1460ee13c8`

The branch contains bounded long-term character/place affinity, familiarity/decay, favorite-place logic, policy integration, Godot affinity harness/stress changes, and a fix for using reserved GDScript keyword `signal` as a parameter name.

Do not merge or continue expanding D4/D5 until canonical source reconciliation is complete or an explicit human decision changes priorities.

## Still blocked / unverified

- **Canonical application source:** external FULL ZIP containing healthy `app.py` must be provided/recovered and reconciled into Git. All in-Git recovery candidates are unsafe/invalid.
- **Backend/UI:** cannot be called verified while `app.py` is absent; current CI correctly skips this job and emits source-blocked status.
- **Full user-facing vertical slice:** the new headless core slice does not include real graphical import/cutout/edit/save/reload workflow.
- A2 real DWPose/RTMPose accuracy: no validated ONNX model artifact/source.
- Final rendered Windows FPS/CPU/GPU/memory at 200–500 characters remains unmeasured.
- `KROLIK_MASTER_PLAN.md` remains absent; use `docs/AUTONOMOUS_RUNBOOK.md`.
- Dedicated eyelid/eye/mouth geometry is not present; eye/mouth facial values remain semantic channels until suitable source geometry exists.

## Next highest-priority task

**Priority #1 remains canonical source reconciliation. Do not start another AI-depth block.**

When `KROLIK_Collection_Vault_FULL_2026-09-13_2158.zip` becomes accessible, follow `docs/SOURCE_RECONCILIATION.md`: hash/CRC/zip-slip validate, extract isolated, diff file-by-file, transplant exact missing `app.py`, preserve newer runtime/core work, run full backend/UI + core + Godot CI, then create a canonical-source checkpoint.

After source reconciliation, expand the newly verified headless core slice into the actual user-facing vertical slice:
1. graphical import of a real character image;
2. cutout preparation;
3. real pose backend or editable fallback rig;
4. visible joint correction;
5. skin/runtime preview;
6. launch the same exported package in Godot;
7. save character/world state;
8. restart and reload;
9. validate on Windows.

If the FULL ZIP is still unavailable during an hourly autonomous run:
- never guess `app.py` bytes and do not retry corrupt recovery repeatedly;
- improve the **same vertical path**, not AI breadth: e.g. generalize the verified package builder to a user-supplied cutout/CLI, add diverse source-image fixtures, tighten runtime-package validation, or advance A2 model acquisition/validation if a legitimate model source becomes available;
- keep 200–500-character performance and Windows validation in scope;
- leave D4/D5 paused.
