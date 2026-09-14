# AUTONOMOUS STATE

Last updated: 2026-09-14 21:38 +03:00

## Current verified implementation

Latest verified code/test commit: `a64a66388c7bb467bf79275ed2609820fc69a89d` (`ci: gate short-term memory runtime`).

Stable checkpoints for current AI work:
- `checkpoint/stable-d1-ai-policy-sync-20260914-2113` — generated/versioned Python→Godot AI policy sync.
- `checkpoint/stable-d2-personality-traits-20260914-2122` — backward-compatible personality traits + optimized runtime bias cache.
- `checkpoint/stable-d3-short-term-memory-20260914-2136` — bounded/decaying short-term memory with cached runtime influence.

Rollback checkpoints include `checkpoint/pre-d2-personality-traits-20260914-2116` and `checkpoint/pre-d3-short-term-memory-20260914-2126`. Earlier Phase A/B/C checkpoints remain preserved.

No rig/skin/animation contract changed. AI policy remains `krolik.ai-policy/1`, format version 1. D2/D3 extend the existing mind semantics without introducing a second AI system.

## Phase status

- Phase A: A1/A3/A5 verified; A4 Linux/headless verified; A2 blocked on validated DWPose/RTMPose ONNX model; rendered Windows 200–500-agent measurement pending.
- Phase B: external animation/fixture/pose content pipeline verified; legacy graphical UI integration blocked because validated `app.py` is absent.
- Phase C: complete for current source-asset capabilities: 33-clip motion library, angle-limited IK, additive layers, production secondary motion, semantic facial/mood state.
- Phase D: D1 generated policy sync VERIFIED; D2 personality VERIFIED; D3 short-term memory VERIFIED. Next unblocked item: D4 long-term affinity/favorite places.

## D1 — generated AI policy sync VERIFIED

`life_sim.py` owns semantic/tuning policy. `ai_policy.py` validates it and `tools/export_ai_policy.py` verifies both committed copies (`content/ai/default_policy_v1.json` and `runtime_godot/data/ai_policy_v1.json`). Godot loads the policy through a static cache and does not require Python at runtime.

## D2 — personality traits VERIFIED

Five bounded traits (`curiosity`, `sociability`, `boldness`, `patience`, `resilience`) are neutral at `0.5`, so legacy profiles remain behaviorally compatible. Trait effects are policy-owned. Runtime precomputes the six state biases instead of traversing nested dictionaries each physics tick.

Godot proof:
`KROLIK_PERSONALITY legacy_neutral=true curious=inspect sociable=social bold=wander patient=idle production=social traits=5`.

## D3 — bounded short-term memory VERIFIED

Short-term memory is a compact optional layer over needs/personality, not a replacement brain.

Policy-owned limits/semantics:
- capacity: `8` entries per agent;
- entry identity: `kind + subject`;
- fields: `kind`, `subject`, signed `valence`, `importance`, `age`, `ttl`;
- default TTL `180s`, max TTL `900s`, subject length max `64`;
- deterministic refresh/dedupe and weakest-retention eviction;
- memory kinds: `interesting`, `social`, `home`, `threat`, `rest`;
- total per-state memory nudge hard-capped at `±0.35`;
- named memories are strongest when current context focuses the same subject and use reduced unfocused relevance otherwise;
- disabled/contained/exhaustion hard gates execute before memory-influenced utility, so memory cannot override them;
- empty memory contributes exactly zero and preserves legacy decisions.

Python exposes `normalize_short_term_memory`, `remember_event`, `step_memory`, `memory_utility_bias` and memory-aware `activity_scores`/`choose_state`/`step_mind`.

Godot `VaultAgentBrain` mirrors these semantics. To keep the 200–500-character target viable, it does not loop over memory every physics tick: it precomputes per-state base+slope decay and next expiry when memory changes; full work is bounded to at most eight entries on insert/expiry. Focus-specific corrections are also precomputed by subject.

Godot proof:
`KROLIK_MEMORY capacity=8 dedupe=true expired=true legacy=idle unfocused=idle focused=social hard_gate=contained production_entries=1 production_state=social`.

Final 220-agent D3 stress proof:
- active `220/220`;
- facial controllers `220/220`;
- generated AI policy `220/220`;
- non-neutral personalities `220/220`;
- non-empty bounded memory `220/220`;
- all five personality families present, `44` each;
- moved `220/220`, moved_share `1.000`, avg travel `99.59 px`;
- 180 physics frames in `2.9201s`, simulated `61.64 FPS`;
- max RSS `121552 KiB` (~119 MiB), under 512 MiB budget;
- process status `0`.

The stress state distribution was `inspect: 44`, `wander: 176`; memory/personality remained active without stalling locomotion.

## Tests/checks actually run

No local execution is claimed; verification came from GitHub Actions.

Final D3 commit `a64a66388c7bb467bf79275ed2609820fc69a89d`:

Vault CI `34881517299`: SUCCESS.
- source-integrity PASS;
- Python syntax PASS;
- generated-policy sync PASS: `KROLIK_AI_POLICY_SYNC targets=2 status=clean`;
- content validation PASS: `files=4 failed=0`;
- core regression suite PASS: `60 passed`;
- backend/UI SKIPPED because validated `app.py` is absent.

Godot Runtime CI `34881517303`: SUCCESS.
- verified Godot 4.7.2 import/headless smoke PASS;
- generated AI policy PASS;
- personality PASS;
- new short-term memory regression PASS;
- animation validation, 33-clip runtime, additive layers, facial state, secondary motion, IK PASS;
- rendered Skeleton2D/Polygon2D deformation PASS with changed pixels total `23867`, evidence uploaded;
- 220-agent memory/personality stress PASS with metrics above.

## Still blocked / unverified

- A2 real DWPose/RTMPose accuracy: no validated ONNX model artifact/source.
- Final rendered Windows FPS/CPU/memory at 200–500 characters remains unmeasured.
- Validated legacy `app.py` is unavailable; backend/UI and direct graphical editor integration remain blocked. Do not reconstruct or guess corrupted bytes.
- `KROLIK_MASTER_PLAN.md` remains absent; follow `docs/AUTONOMOUS_RUNBOOK.md`.
- Dedicated eyelid/eye/mouth geometry is not present; eye/mouth values remain semantic channels.
- Existing `krolik.runtime-character/1` package already has an opaque `mind.runtime` extension payload, but D3 does not silently change that versioned manifest contract. A persistence bridge from stored runtime memory into the Godot brain should be added only in a contract-compatible way (or with an explicit schema/version migration), not by silently adding a new manifest field.

## Next highest-priority task

D4 long-term affinity/favorite places:
1. Define compact bounded long-term affinity records keyed by character/place IDs, independent from transient D3 memory.
2. Use slow bounded learning/decay with hard capacity and neutral defaults so legacy behavior is unchanged.
3. Let affinity alter social target preference and favorite-place/home-return utility only within policy-owned caps.
4. Keep per-frame cost cached/near-zero; updates occur on encounters/events rather than scanning hundreds of relationships every frame.
5. Mirror semantics in Python/Godot, add behavioral/eviction/round-trip regressions and include representative affinity data in the 220-agent stress gate before declaring D4 stable.
