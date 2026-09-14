# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 10.

## Current main / rollback

- Current runtime/CI implementation commit: `cfec1162ce8ebec11a423e4b523e651ae97c6f5d` (`ci: diagnose and harden stress harness timeout`).
- New rollback checkpoint created before this change: `checkpoint/pre-ci-stress-timeout-20260914` at `50efae0077068dddc826cc0540fda192c417ff08`.
- Earlier pre-A1 rollback checkpoint remains `checkpoint/pre-a1-render-deform-20260914`.
- No application/schema/data contract changed in this pass.

## Repository integrity status

The validated Python/editor application source (`app.py` and related UI/tests) is still absent, so Python application feature work remains blocked. The canonical recovery transport remains incomplete (`tools/source_restore_parts/part_10.b64` absent); never guess missing source bytes. Vault CI's source-integrity gate remains intentional until restoration.

The Godot runtime tree is independently present and testable.

## Work completed in pass 10

1. Read `docs/AUTONOMOUS_RUNBOOK.md`, the previous autonomous state, repository roadmap material, current runtime scripts/workflow, latest main commit and Actions state before editing.
2. Inspected Godot Runtime CI run `34811668598` from pass 9. It completed **failure** in `220 live-agent stress smoke with RSS budget`; `Parse and import Godot project` and `Headless runtime smoke` both succeeded. This proves the optional `KROLIK_STRESS_METRIC` parser was not the root cause.
3. Created rollback branch `checkpoint/pre-ci-stress-timeout-20260914` before modifying the workflow.
4. Hardened the stress process watchdog in `.github/workflows/godot-runtime.yml`: the external timeout is now 90 seconds with TERM then a 10-second kill grace. The harness's own measured-runtime assertion remains unchanged, so a genuine simulation performance regression still fails inside the harness; hosted-runner startup/teardown slowness no longer has to fit inside the previous 45-second outer watchdog.
5. Added process status to the stress summary and explicit timeout-tail diagnostics for exit 124/137. RSS <= 512 MiB and non-zero harness status remain mandatory gates.
6. Pushed implementation commit `cfec1162ce8ebec11a423e4b523e651ae97c6f5d` to `main`. New Godot Runtime CI run `34819317736` and Vault CI run `34819317704` started automatically.

## Tests / verification actually performed

- Godot Runtime CI run `34811668598` for previous commit `8c382a3b932f4fd500e263d07f74a88c1e2c9e8f`: **failure**. Project parse/import: success. Ordinary headless runtime smoke: success. 220-agent stress/RSS step: failure.
- New Godot Runtime CI run `34819317736` for `cfec1162ce8ebec11a423e4b523e651ae97c6f5d`: **in progress** at state-write time. Do not claim the watchdog repair verified until it completes.
- New Vault CI run `34819317704`: **in progress** at state-write time. While `app.py` is absent, a green result is source-integrity status only, not backend/UI verification.
- No Python application tests were run because validated Python/editor source remains absent.

## Anything still unverified

- Exact exit reason/output of the prior stress failure was not exposed by the available connector response, so the 90-second watchdog repair is intentionally instrumented to make a repeated timeout diagnosable rather than pretending the root cause is proven.
- Whether Godot Runtime CI run `34819317736` passes the real harness-exit/RSS gates.
- Exact Linux/headless RSS/FPS baseline from the new run.
- Rendered/Windows performance remains unmeasured, so A4 is not complete.

## Exact blockers / safe continuation

Primary restoration blocker remains a byte-exact copy of the validated stable Python/editor source artifact (or complete exact base64 transport). Do not reconstruct it by guessing.

Next pass should:

1. Inspect Godot Runtime CI run `34819317736` first. If it failed, use the new process-status/timeout-tail diagnostics to identify the real stress failure and fix it before feature work. If it succeeded, record the verified RSS/FPS/process status and preserve a stable checkpoint at the verified commit.
2. Once CI is green, continue A1 visual deformation verification. Build a deterministic Godot test around the existing `VaultSkinnedCharacter`/`Skeleton2D`/`Polygon2D` path that proves a bone transform produces actual mesh/render deformation; prefer image/pixel evidence when a CI-safe renderer is available, otherwise establish deterministic geometry deformation assertions first and add rendered evidence next.
3. Do not call A4 complete until rendered Windows FPS/CPU/memory is measured. Linux/headless CI remains a regression baseline only.

## CI semantics until restoration

`Vault CI` distinguishes repository/source integrity from application verification. While `app.py` is absent, green Vault CI means only that recovery state was detected correctly. Godot Runtime CI is independently meaningful for the present `runtime_godot` tree and includes active 220-agent locomotion plus process-RSS regression coverage.
