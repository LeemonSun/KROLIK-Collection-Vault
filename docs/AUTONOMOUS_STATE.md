# AUTONOMOUS STATE

Last updated: 2026-09-14 21:24 +03:00

## Current verified implementation

Latest verified code/test commit: `a414fd08c00bfce59ed079ed22eb693d6d1e3045` (`perf: cache personality utility biases`).

Stable checkpoints for current AI work:
- `checkpoint/stable-d1-ai-policy-sync-20260914-2113` — generated/versioned Python→Godot AI policy sync.
- `checkpoint/stable-d2-personality-traits-20260914-2122` — backward-compatible personality traits + optimized runtime bias cache.

Rollback checkpoint for D2: `checkpoint/pre-d2-personality-traits-20260914-2116`.
Earlier verified Phase A/B/C checkpoints remain preserved, including the C5 facial/mood checkpoint.

No rig/skin/animation contract changed. AI policy remains `krolik.ai-policy/1`, format version 1. Personality traits extend the existing mind profile without a separate AI system or breaking old profiles.

## Phase status

- Phase A: A1/A3/A5 verified; A4 Linux/headless verified; A2 blocked on validated DWPose/RTMPose ONNX model; rendered Windows 200–500-agent measurement pending.
- Phase B: external animation/fixture/pose content pipeline verified; legacy graphical UI integration blocked because validated `app.py` is absent.
- Phase C: complete for current source-asset capabilities: 33-clip motion library, angle-limited IK, additive layers, production secondary motion, semantic facial/mood state.
- Phase D: D1 generated AI policy sync VERIFIED; D2 personality traits VERIFIED. Next unblocked item is D3 short-term memory.

## D1 — generated AI policy sync VERIFIED

`life_sim.py` owns the semantic/tuning AI policy. `ai_policy.py` validates it and `tools/export_ai_policy.py` reproducibly verifies both committed copies:
- `content/ai/default_policy_v1.json`;
- `runtime_godot/data/ai_policy_v1.json`.

Vault CI fails on drift. `VaultAgentBrain` loads the runtime policy through a static cache and uses policy-owned utility coefficients, hard gates, state order, need rates, affect thresholds and enum sets. Invalid/missing policy retains deterministic fallback and runtime does not require Python.

Godot proof remains:
`KROLIK_AI_POLICY schema=krolik.ai-policy/1 source=harness-custom default_state=social overridden_state=idle energy_after_rate=0.600 production_state=social production_loaded=true`.

## D2 — personality traits VERIFIED

Personality is a neutral, backward-compatible layer over the existing policy. The five bounded traits are:
- `curiosity` — biases inspect/exploration;
- `sociability` — biases social activity;
- `boldness` — biases wandering vs return-home;
- `patience` — biases remaining idle;
- `resilience` — reduces rest/return-home preference.

Each trait is clamped to `[0,1]`; `0.5` is neutral. Missing traits therefore preserve legacy behavior exactly. Traits live inside the existing profile snapshot and round-trip through `VaultAgentBrain.snapshot()`.

The generated AI policy owns the trait effect coefficients. Python and Godot consume the same policy semantics; there is no hand-coded second personality table in Godot.

Python behavioral regressions prove identical needs/context can produce different choices solely from personality: curious→`inspect`, sociable→`social`, bold→`wander`, patient→`idle`, while missing traits match explicit neutral traits.

Godot production regression proves the same decisions, bounds and CharacterAgent round-trip:
`KROLIK_PERSONALITY legacy_neutral=true curious=inspect sociable=social bold=wander patient=idle production=social traits=5`.

The first mixed-personality stress run was functionally correct but exposed a real performance regression from per-tick nested trait/effect dictionary iteration: `31.90 FPS` at 220 agents. The block was not declared stable at that point. `VaultAgentBrain` now precomputes the six per-state personality utility biases whenever policy/profile personality changes; physics ticks only consume cached values. Final stress improved to `51.17 FPS` on the GitHub runner while keeping all behavior/load gates intact.

Final 220-agent D2 stress proof:
- active `220/220`;
- facial controllers `220/220`;
- generated AI policy `220/220`;
- non-neutral personality `220/220`;
- all five trait families present, exactly `44` agents each;
- moved `220/220`, moved_share `1.000`, avg_travel `99.59 px`;
- 180 physics frames in `3.5173 s`, simulated `51.17 FPS`;
- max RSS `118864 KiB` (~117 MiB), well below 512 MiB budget;
- process status `0`.

## Tests/checks actually run

No local execution is claimed; verification came from GitHub Actions.

Final D2 commit `a414fd08c00bfce59ed079ed22eb693d6d1e3045`:

Vault CI `34880199317`: SUCCESS.
- source-integrity PASS;
- Python syntax PASS;
- generated-policy sync PASS: `KROLIK_AI_POLICY_SYNC targets=2 status=clean`;
- content validation PASS: `files=4 failed=0`;
- core regression suite PASS: `55 passed`;
- backend/UI SKIPPED because validated `app.py` is absent.

Godot Runtime CI `34880199359`: SUCCESS.
- verified Godot 4.7.2 download/hash, project import and headless smoke PASS;
- generated AI policy runtime regression PASS;
- D2 personality runtime regression PASS;
- animation validation, 33-clip runtime, layered animation, facial state, secondary motion and IK limits PASS;
- rendered Skeleton2D/Polygon2D deformation PASS, changed pixels total `23867`, evidence uploaded;
- final mixed-personality 220-agent stress PASS with the metrics listed above.

## Still blocked / unverified

- A2 real DWPose/RTMPose accuracy: no validated ONNX model artifact/source.
- Final rendered Windows FPS/CPU/memory at 200–500 characters remains unmeasured.
- Validated legacy `app.py` is unavailable; backend/UI and direct graphical editor integration remain blocked. Do not reconstruct or guess corrupted bytes.
- `KROLIK_MASTER_PLAN.md` remains absent; follow `docs/AUTONOMOUS_RUNBOOK.md`.
- Dedicated eyelid/eye/mouth geometry is not present; facial eye/mouth values remain semantic channels until suitable source geometry exists.
- D2 still has measurable personality CPU cost vs the previous D1-only stress reference (~51 FPS vs ~60 FPS on different GitHub runners); do not over-interpret cross-run numbers. Phase F should perform same-run profiling/LOD optimization rather than weakening current correctness gates.

## Next highest-priority task

Start D3 short-term memory as a bounded runtime/profile capability, keeping the 200–500-character target in scope:
1. Define compact bounded memory entries (event/type, subject/entity id, valence/importance, age/TTL) with hard per-agent capacity.
2. Provide deterministic insert/update/decay/eviction rules so memory cannot grow without bound.
3. Let recent relevant memories make small, policy-owned utility adjustments without replacing needs/personality.
4. Preserve empty-memory behavior exactly for legacy profiles.
5. Mirror the same semantics in Python and Godot or export policy-owned coefficients as in D1/D2.
6. Add Python behavioral/eviction regressions and a Godot runtime harness; include non-empty bounded memory in the 220-agent stress gate before declaring D3 stable.
