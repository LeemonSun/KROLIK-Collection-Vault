# AUTONOMOUS STATE

Last updated: 2026-09-14 22:22 +03:00

## Current repository state

Current `main` implementation/documentation head: `5173c7f690a5d9b3ef550f16e179714bd602f2e1` (`ci: expose canonical source readiness and audit recovery artifacts`).

Current verified runtime feature baseline: `a64a66388c7bb467bf79275ed2609820fc69a89d` (`ci: gate short-term memory runtime`).

Stable checkpoints relevant to current work:
- `checkpoint/stable-d1-ai-policy-sync-20260914-2113` — generated/versioned Python→Godot AI policy sync.
- `checkpoint/stable-d2-personality-traits-20260914-2122` and later `checkpoint/stable-d2-personality-traits-20260914-2124` — backward-compatible personality traits + optimized runtime bias cache.
- `checkpoint/stable-d3-short-term-memory-20260914-2136` — bounded short-term memory runtime.
- `checkpoint/stable-d3-source-readiness-20260914-2222` — verified D3 baseline plus explicit canonical-source readiness audit.

No rig/skin/animation format contract changed in this reconciliation block. AI policy remains `krolik.ai-policy/1`, format version 1.

## Critical source-of-truth correction

A full external project snapshot named `KROLIK_Collection_Vault_FULL_2026-09-13_2158.zip` is known from an independent review to have contained a healthy, substantial `app.py` backend. That exact external ZIP is not currently available to this GitHub connector/session.

The current Git repository does **not** contain a canonical `app.py`, and exhaustive in-repository recovery checks prove that the historical mirrors are not safe authoritative replacements:

- `tools/source_restore.zip`: present but not a valid ZIP; SHA-256 `1a3a8ec920980f842b3032a875a71bf2dd6d9d5807d77a85829ff8ab6b6da869`.
- canonical `tools/source_restore_parts/part_00..part_10.b64`: incomplete because the canonical set is missing.
- historical original `part_07` combination: invalid base64 transport.
- historical corrected `part_07` combination: decodes to a valid ZIP containing `app.py`, but `archive.testzip()` reports CRC failure specifically for `app.py`; payload SHA-256 `057cacf29919636b0ec66ed82ea9fa16dd524fd928d68cb9b6df5c49f715bfdc`.
- legacy `.source_sync` chunks: not a valid ZIP; SHA-256 `948dcb40911ff5687b8c7f28efe39f9a6beea31fc7f9c0a7c66a979a55e7c180`.

Therefore **do not reconstruct, guess, patch, or synthesize `app.py` bytes from the damaged in-Git recovery artifacts**.

The new non-destructive `tools/audit_source_readiness.py` is now the canonical source-readiness check. It reports `present`, `recoverable`, or `blocked` and never writes restored files.

Current machine result from Vault CI:
`KROLIK_SOURCE_READINESS status=blocked app_present=false recoverable=false`

Vault CI now emits `FULL PRODUCT SOURCE BLOCKED` when `app.py` is absent. Core/runtime CI may still be green, but backend/UI is explicitly **not counted as verified**.

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
- Phase B: external animation/fixture/pose content pipeline VERIFIED. Graphical backend/UI source is now explicitly SOURCE-BLOCKED until the authoritative FULL ZIP is reconciled.
- Phase C: VERIFIED for current source-asset capabilities: 33-clip motion library, angle-limited IK, additive layers, production secondary motion, semantic facial/mood state.
- Phase D: D1 VERIFIED; D2 VERIFIED; D3 short-term memory VERIFIED. D4 long-term affinity exists as unverified work on a recovery branch and is PAUSED while source reconciliation has higher priority.

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

The original nested dictionary hot path caused ~31.90 FPS at 220 agents; cached per-state trait biases recovered the same stress class to ~51.17 FPS without weakening correctness gates.

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

Final D3 Godot Runtime CI `34881517303`: SUCCESS.
- verified Godot 4.7.2 download/hash and project import PASS;
- headless runtime smoke PASS;
- generated AI policy runtime PASS;
- personality runtime PASS;
- short-term memory runtime PASS;
- animation validation / 33-clip runtime / layered animation / facial state / secondary motion / IK limits PASS;
- rendered Skeleton2D/Polygon2D deformation PASS: tall changed pixels `10182`, compact `13685`, total `23867`;
- 220-agent stress PASS.

Final D3 stress proof:
- agents `220`, active `220`;
- facial_active `220`;
- ai_policy_active `220`;
- personality_active `220`;
- memory_active `220`;
- 180 real physics frames in `2.9201 s`;
- simulated `61.64 FPS`;
- moving `220`, moved `220`, moved_share `1.000`;
- avg_travel `99.59 px`;
- avg_phase `3.48`;
- states `{inspect: 44, wander: 176}`;
- five personality families, 44 agents each;
- max RSS `121552 KiB` (~119 MiB), below 512 MiB budget;
- process status `0`.

Vault CI on D3 `34881517299`: SUCCESS for core/source-readiness-era checks at that commit.
- Python syntax PASS;
- generated-policy sync PASS;
- content validation `files=4 failed=0`;
- D3 core regression suite PASS (60 tests at that revision);
- backend/UI SKIPPED because canonical `app.py` was absent.

## Canonical source-readiness hardening VERIFIED

Commit chain ending at `5173c7f690a5d9b3ef550f16e179714bd602f2e1` added:
- `tools/audit_source_readiness.py` — read-only source/recovery audit;
- `tests/test_source_readiness.py` — regression coverage for present/recoverable/blocked cases and no-write behavior;
- explicit `canonical-source-readiness` CI job;
- explicit `FULL PRODUCT SOURCE BLOCKED` warning and job summary when `app.py` is absent;
- backend/UI remains conditional on actual canonical source presence.

Vault CI `34886425415`: SUCCESS for the audit/core pipeline.
- canonical source audit executed and correctly reported BLOCKED;
- Python syntax PASS;
- generated AI policy sync PASS: `targets=2 status=clean`;
- content validation PASS: `files=4 failed=0`;
- core regression suite PASS: 64 tests total at this revision;
- backend/UI SKIPPED and explicitly not counted as verified.

This green Vault CI means **core + audit are healthy**, not that the full product/backend/UI is healthy.

## D4 — long-term affinity work PAUSED / UNVERIFIED

Preserved work branch:
`work/d4-long-term-affinity-recovery-20260914`

Current head:
`08ff0c113f268a775265f387adba1c1460ee13c8`

The branch contains bounded long-term character/place affinity, familiarity/decay, favorite-place logic, policy integration, Godot affinity harness/stress changes, and a fix for using reserved GDScript keyword `signal` as a parameter name.

Do not merge or continue expanding D4/D5 until canonical source reconciliation is complete or an explicit human decision changes priorities.

## Still blocked / unverified

- **Canonical application source:** external FULL ZIP containing healthy `app.py` must be provided/recovered and reconciled into Git. All in-Git recovery candidates are currently unsafe/invalid.
- **Backend/UI:** cannot be called verified while `app.py` is absent; current CI correctly skips this job and emits source-blocked status.
- A2 real DWPose/RTMPose accuracy: no validated ONNX model artifact/source.
- Final rendered Windows FPS/CPU/GPU/memory at 200–500 characters remains unmeasured.
- `KROLIK_MASTER_PLAN.md` remains absent; use `docs/AUTONOMOUS_RUNBOOK.md`.
- Dedicated eyelid/eye/mouth geometry is not present; eye/mouth facial values remain semantic channels until suitable source geometry exists.

## Next highest-priority task

**Do not start another AI-depth block. Canonical source reconciliation is priority #1.**

When the authoritative `KROLIK_Collection_Vault_FULL_2026-09-13_2158.zip` becomes accessible:
1. Hash the exact ZIP and list members; keep the original immutable.
2. Validate ZIP structure/CRC and reject zip-slip/path traversal before extraction.
3. Extract into an isolated integration workspace/branch.
4. Compare every recovered source file against current `main`.
5. `app.py` is absent from current Git, so transplant the exact healthy source rather than reconstructing it.
6. For files that exist in both snapshot and modern `main`, preserve newer runtime/core changes unless a file-level review proves the snapshot contains required missing code.
7. Re-enable and run full backend/UI validation: `py_compile app.py`, full pytest, HTTP smoke, headless UI smoke, and UI artifact.
8. Run current core Python CI and Godot runtime CI on the reconciled branch.
9. Create a stable canonical-source checkpoint only after all applicable checks are green.
10. Then build one end-to-end user vertical slice before resuming D4/D5 depth.

If the FULL ZIP is still unavailable during an autonomous hourly run, do not guess bytes and do not spend the whole run retrying corrupt recovery. Advance only source-independent work that directly supports the next end-to-end vertical slice or A2/Windows validation, and record exact limitations.
