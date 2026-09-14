# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 5.

## Current main / rollback

- Latest verified runtime code block: `7dca2a5d62ed78b58eaad6768e15344de0b61e2` (`Drive deterministic physics ticks in stress harness`).
- Pre-change rollback checkpoint: `checkpoint/pre-active-stress-20260914-0455` at `32e029f1e443f0feedaf6e679158b87ccafecb0d`.
- No application/schema/data contract changed in this pass.

## Repository integrity status

The validated Python/editor application source (`app.py` and related UI/tests) is still absent, so Python application feature work remains blocked. The canonical recovery transport remains incomplete (`tools/source_restore_parts/part_10.b64` absent); never guess missing source bytes. Vault CI's source-integrity gate remains intentional until restoration.

The Godot runtime tree is independently present and testable, so this pass continued Phase A runtime performance verification.

## Work completed in pass 5

1. Hardened `runtime_godot/scripts/stress_harness.gd` so all 220 real `VaultCharacterAgent` nodes execute sustained locomotion rather than merely remaining alive.
2. Added deterministic fixed-delta physics driving for headless CI. The harness disables automatic scheduling for benchmark agents and calls their real `_physics_process()` path exactly once per fixed tick, removing headless scheduling ambiguity while retaining brain, animation, movement and `CharacterBody2D.move_and_slide()` work.
3. Added behavior assertions: at least 80% of agents must travel >=8 px during the benchmark; telemetry now reports moving count, moved count/share and average travel.
4. First implementation using passive SceneTree scheduling correctly failed the new assertion (`moving=0`, `moved=0`), proving the assertion catches a non-exercised benchmark. It was replaced by deterministic physics ticks rather than weakening the requirement.
5. Created rollback checkpoint `checkpoint/pre-active-stress-20260914-0455` before the change.

## Tests / verification actually performed

GitHub Actions `Godot Runtime CI` run `34797585790`, job `103833576413`, completed **success** on Godot `4.7.2.stable`:

- verified Godot download/hash: success;
- parse/import project: success;
- existing headless runtime smoke: success;
- 220-agent active locomotion stress smoke: success;
- telemetry: `agents=220 active=220 frames=180 seconds=4.9003 avg_fps=36.73 moving=220 moved=220 moved_share=1.000 avg_travel=222.19`.

A deliberately stricter intermediate run `34797544312` failed with `moved_share=0.000`, which exposed that passive headless scheduling was not exercising locomotion; this was fixed in the verified commit above.

Interpretation: 220 full agents can execute the current brain/animation/movement/CharacterBody2D physics path for the measured window with 100% locomotion coverage on the hosted Ubuntu runner. The deterministic harness processes simulation ticks as fast as possible, so `avg_fps=36.73` is throughput-equivalent telemetry, not rendered game FPS. This remains a non-rendered Linux CI measurement, not a Windows/GPU claim.

No Python application tests were run because the validated Python/editor source remains absent. A green Vault CI in this recovery state is source-integrity status only, not backend/UI coverage.

## Exact blockers / safe continuation

Primary restoration blocker remains a byte-exact copy of the validated stable Python/editor source artifact (or complete exact base64 transport). Do not reconstruct it by guessing.

Next pass should:

1. Check first whether the exact stable source artifact has become available. If yes, regenerate all canonical recovery chunks, validate ZIP CRC, restore, then require `py_compile`, full pytest, HTTP/UI smokes, Vault CI and Godot Runtime CI before a stable-source checkpoint.
2. If source is still unavailable, continue A4 by adding process-memory telemetry to the stress workflow/harness and a conservative regression budget. Prefer runner-level RSS measurement around the Godot stress process because Godot's internal memory counters do not represent total process memory. Preserve the active-locomotion assertion.
3. Then pursue A1 visual deformation verification using repository-contained synthetic/reference assets if available. Do not call A4 complete until rendered Windows FPS/CPU/memory is measured; current CI provides a strong Linux/headless regression baseline only.

## CI semantics until restoration

`Vault CI` distinguishes repository/source integrity from application verification. While `app.py` is absent, green Vault CI means only that recovery state was detected correctly. Godot Runtime CI is independently meaningful for the present `runtime_godot` tree and now includes active 220-agent locomotion stress coverage.
