# AUTONOMOUS STATE

Last updated: 2026-09-14 21:14 +03:00

## Current verified implementation

Latest verified code/test commit: `aebd5685fd9a919d2da6e362574c0808490fb32e` (`test: validate complete AI hard gate policy`).

Stable checkpoint: `checkpoint/stable-d1-ai-policy-sync-20260914-2113`.
Rollback checkpoint: `checkpoint/pre-d1-ai-policy-sync-20260914-2104`.
Earlier verified Phase A/B/C checkpoints remain preserved, including `checkpoint/stable-c5-facial-mood-20260914-2101`.

No versioned rig/skin/animation contract changed. D1 introduces a new independent AI policy contract: `krolik.ai-policy/1`, format version 1. Existing mind snapshot structure remains backward-compatible.

## Phase status

- Phase A: A1/A3/A5 verified; A4 Linux/headless verified; A2 blocked on validated DWPose/RTMPose ONNX model; rendered Windows 200–500-agent measurement pending.
- Phase B: external animation/fixture/pose content pipeline verified; legacy graphical UI integration blocked because validated `app.py` is absent.
- Phase C: complete for current source-asset capabilities: 33-clip motion library, angle-limited IK, additive layers, production secondary motion, semantic facial/mood state.
- Phase D: D1 VERIFIED. Next unblocked item is D2 personality traits.

## D1 — generated AI policy sync VERIFIED

`life_sim.py` is now the semantic and tuning source of truth. It owns a versioned `AI_POLICY` document containing defaults, valid mobility/routine/bound modes, utility state order, hard gates, utility coefficients, target/routine bonuses, need rates, affect thresholds and animation mapping. The final formerly duplicated rest-ready multiplier is also policy-owned.

`ai_policy.py` validates the portable contract. `tools/export_ai_policy.py` reproducibly generates/checks both committed copies:
- `content/ai/default_policy_v1.json`;
- `runtime_godot/data/ai_policy_v1.json`.

Vault CI fails if either copy drifts from `life_sim.py`. `tools/validate_content.py` now includes AI policy assets alongside animation/fixture/pose content.

`VaultAgentBrain` loads the bundled policy once through a static cache, so hundreds of agents do not reread JSON. Utility coefficients, hard gates, state order, need rates, affect thresholds and valid enum sets are policy-driven. Invalid/missing policy retains deterministic built-in fallback and does not require Python at runtime.

`ai_policy_harness.gd` proves the runtime is actually data-driven: the default policy selects `social`; a valid runtime policy override changes the same brain decision to `idle` and changes a 60-second energy rate from 0.50 to 0.60 without GDScript code changes; invalid policy is rejected without replacing the active one. A real `VaultCharacterAgent` also loads the generated policy and makes the expected production decision.

Verified runtime metric:
`KROLIK_AI_POLICY schema=krolik.ai-policy/1 source=harness-custom default_state=social overridden_state=idle energy_after_rate=0.600 production_state=social production_loaded=true`.

The 220-agent stress gate now requires every production brain to report a loaded generated policy in addition to the existing facial/movement gates.

## Tests/checks actually run

No local execution is claimed; verification came from GitHub Actions.

Vault CI `34879229207` for `aebd5685fd9a919d2da6e362574c0808490fb32e`: SUCCESS.
- source-integrity PASS;
- Python syntax PASS;
- generated-policy sync PASS: `KROLIK_AI_POLICY_SYNC targets=2 status=clean`;
- content validation PASS: `files=4 failed=0`;
- core regression suite PASS: `52 passed`;
- backend/UI SKIPPED because validated `app.py` is absent.

Godot Runtime CI `34879229415` for the same commit: SUCCESS.
- Godot 4.7.2 verified download/hash, project import and headless smoke PASS;
- generated AI policy runtime regression PASS;
- animation validation, 33-clip runtime, layered animation, facial state, secondary motion and IK limits PASS;
- rendered Skeleton2D/Polygon2D deformation PASS, changed pixels total `23867`, evidence uploaded;
- 220-agent stress PASS: `active=220`, `facial_active=220`, `ai_policy_active=220`, `moved=220`, `moved_share=1.000`, `sim_fps=60.06`, `avg_travel_px=99.59`, max RSS `117040 KiB` (~115 MiB), process status 0.

## Still blocked / unverified

- A2 real DWPose/RTMPose accuracy: no validated ONNX model artifact/source.
- Final rendered Windows FPS/CPU/memory at 200–500 characters remains unmeasured.
- Validated legacy `app.py` is unavailable; backend/UI and direct graphical editor integration remain blocked. Do not reconstruct or guess corrupted bytes.
- `KROLIK_MASTER_PLAN.md` remains absent; follow `docs/AUTONOMOUS_RUNBOOK.md`.
- Dedicated eyelid/eye/mouth geometry is not present; facial eye/mouth values remain semantic channels until suitable source geometry exists.

## Next highest-priority task

Start D2 personality traits as a backward-compatible extension of the existing mind profile rather than a parallel AI system:
1. Define a bounded default trait set with clear behavioral meaning and no duplication of raw utility weights.
2. Let traits modulate policy utility/rates in Python source-of-truth and Godot through the same generated AI policy contract.
3. Preserve old profiles with neutral defaults and keep existing `routine`, autonomy/social/wander controls valid.
4. Add Python behavioral regressions showing distinct personalities choose differently under identical needs/context.
5. Add a Godot production harness proving the same trait profiles produce the same expected decisions, then stress all 220 agents with mixed deterministic traits.
6. Verify both CI workflows before creating a D2 stable checkpoint.
