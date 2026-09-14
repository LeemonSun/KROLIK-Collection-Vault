# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 4.

## Current main / rollback

- Latest verified runtime block: `32e029f1e443f0feedaf6e679158b87ccafecb0d` (`Run live-agent stress test in Godot CI`).
- Pre-change rollback checkpoint: `checkpoint/pre-godot-stress-harness-20260914-0356` at `20f35d15752762ca6ecee85e0efdaa4480ae589b`.
- No application/schema/data contract changed in this pass.

## Repository integrity status

The validated Python/editor application source (`app.py` and related UI/tests) is still absent, so Python application feature work remains blocked. The canonical recovery transport is still incomplete (`tools/source_restore_parts/part_10.b64` absent); never guess missing source bytes. Vault CI's source-integrity gate remains intentional until restoration.

The Godot runtime tree is independently present and testable, so this pass advanced Phase A runtime infrastructure without touching missing application source.

## Work completed in pass 4

1. Added `runtime_godot/scripts/stress_harness.gd`, a real headless SceneTree stress harness that instantiates **220 actual `VaultCharacterAgent` CharacterBody2D nodes**. Each agent runs the existing brain/animation/navigation/physics process path; these are not lightweight test doubles.
2. Added warmup + 180-frame measured sample, active-agent integrity assertion, elapsed-time guard, and machine-readable `KROLIK_STRESS` telemetry.
3. Wired the harness into `Godot Runtime CI`, after project import and the existing headless runtime smoke, so future runtime changes continuously re-run the 220-agent test.
4. Created rollback checkpoint `checkpoint/pre-godot-stress-harness-20260914-0356` before the runtime/CI change.

## Tests / verification actually performed

GitHub Actions `Godot Runtime CI` run `34794301160`, job `103824327954`, completed **success** on Godot `4.7.2.stable`:

- verified Godot download/hash: success;
- parse/import project: success;
- existing headless runtime smoke: success;
- new 220 live-agent stress smoke: success;
- measured telemetry: `agents=220 active=220 frames=180 seconds=1.2485 avg_fps=144.17 moving=0` on the hosted Ubuntu runner.

Interpretation: the current non-rendered/headless runtime can keep 220 full agent nodes alive and process 180 sampled frames well inside the 20-second guard. This is **not** yet a Windows/rendered GPU performance claim. `moving=0` also means this first harness validates live processing/scale but does not yet exercise sustained locomotion/navigation load.

No Python application tests were run because the validated Python/editor source remains absent. A green Vault CI in this recovery state is source-integrity status only, not backend/UI coverage.

## Exact blockers / safe continuation

Primary restoration blocker remains a byte-exact copy of the validated stable Python/editor source artifact (or complete exact base64 transport). Do not reconstruct it by guessing.

Next pass should:

1. Check first whether the exact stable source artifact has become available. If yes, regenerate all canonical recovery chunks, validate ZIP CRC, restore, then require `py_compile`, full pytest, HTTP/UI smokes, Vault CI and Godot Runtime CI before a stable-source checkpoint.
2. If source is still unavailable, continue repository-safe Phase A Godot work. Highest-value follow-up is to harden A4: force a meaningful share of the 220 agents into sustained movement/navigation, record process memory alongside FPS, and keep thresholds conservative enough for CI variance. After that, pursue A1 visual deformation verification using repository-contained synthetic/reference assets if available.
3. Do not call A4 complete from this pass alone: rendered Windows FPS/CPU/memory and active navigation/locomotion remain unmeasured.

## CI semantics until restoration

`Vault CI` distinguishes repository/source integrity from application verification. While `app.py` is absent, green Vault CI means only that recovery state was detected correctly. Godot Runtime CI is independently meaningful for the present `runtime_godot` tree and now includes the 220-agent stress smoke.
