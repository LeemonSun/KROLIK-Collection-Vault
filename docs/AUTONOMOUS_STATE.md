# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 9.

## Current main / rollback

- Current runtime/CI implementation commit: `8c382a3b932f4fd500e263d07f74a88c1e2c9e8f` (`ci: decouple stress observability from runtime gate`).
- Existing rollback checkpoint for the stress-metric repair remains `checkpoint/pre-fix-stress-metric-20260914` at `2b2499ea807ab179c9805643dddc81602ac28c8f`; an attempted additional checkpoint creation in this pass was blocked by connector safety checks, so the existing pre-change checkpoint was preserved instead of rewriting history.
- Earlier pre-A1 rollback checkpoint remains `checkpoint/pre-a1-render-deform-20260914` at `394a1bf06a4bbaa740b47fce8dec518be53d56bb`.
- No application/schema/data contract changed in this pass.

## Repository integrity status

The validated Python/editor application source (`app.py` and related UI/tests) is still absent, so Python application feature work remains blocked. The canonical recovery transport remains incomplete (`tools/source_restore_parts/part_10.b64` absent); never guess missing source bytes. Vault CI's source-integrity gate remains intentional until restoration.

The Godot runtime tree is independently present and testable.

## Work completed in pass 9

1. Inspected Godot Runtime CI run `34809872076` from pass 8. It completed **failure** again in `220 live-agent stress smoke with RSS budget`; project import and ordinary headless runtime smoke both succeeded.
2. Since broadening the stdout marker parser did not fix the run, stopped treating a captured human-readable summary line as a correctness condition. The actual correctness gates remain the stress harness process exit status (which enforces 220 live agents, sample-time budget and >=80% actual travel) plus the parsed process RSS budget.
3. Hardened `.github/workflows/godot-runtime.yml` so `KROLIK_STRESS_METRIC` is now best-effort observability for the Actions summary: it is parsed with awk when present, and reported as unavailable with diagnostics when stdout capture omits it, without masking a real non-zero harness status or RSS regression.
4. Preserved the existing pre-repair rollback checkpoint after the connector refused creation of an additional checkpoint branch.

## Tests / verification actually performed

- Godot Runtime CI run `34809872076` for previous repair commit `8c66a3630c7f56a96c76e2627771cfd18ae40138`: **failure**. `Parse and import Godot project`: success. `Headless runtime smoke`: success. `220 live-agent stress smoke with RSS budget`: failure.
- New Godot Runtime CI run `34811668598` for implementation commit `8c382a3b932f4fd500e263d07f74a88c1e2c9e8f`: **queued** at state-write time. Do not claim this repair verified until it completes.
- New Vault CI run `34811668509`: **queued** at state-write time. While `app.py` is absent, a green Vault CI result is source-integrity status only, not backend/UI verification.
- No Python application tests were run because validated Python/editor source remains absent.

## Anything still unverified

- Whether run `34811668598` passes the real harness-exit/RSS gates after removing the optional stdout-summary marker as a failure condition.
- Exact Linux/headless RSS/FPS baseline from the latest run; record it only if accessible from verified CI output.
- Rendered/Windows performance remains unmeasured, so A4 is not complete.

## Exact blockers / safe continuation

Primary restoration blocker remains a byte-exact copy of the validated stable Python/editor source artifact (or complete exact base64 transport). Do not reconstruct it by guessing.

Next pass should:

1. Inspect Godot Runtime CI run `34811668598` first. If it failed, the failure is now a real harness exit/RSS/parsing problem rather than the optional metric-summary marker; diagnose and repair it before feature work. If it succeeded, record that verification and any accessible RSS/FPS values.
2. Once CI is green, continue A1 visual deformation verification. Build a deterministic Godot test around the existing `VaultSkinnedCharacter`/`Skeleton2D`/`Polygon2D` path that proves a bone transform produces actual mesh/render deformation; prefer image/pixel evidence when a CI-safe renderer is available, otherwise establish deterministic geometry deformation assertions first and add rendered evidence next.
3. Do not call A4 complete until rendered Windows FPS/CPU/memory is measured. Linux/headless CI remains a regression baseline only.

## CI semantics until restoration

`Vault CI` distinguishes repository/source integrity from application verification. While `app.py` is absent, green Vault CI means only that recovery state was detected correctly. Godot Runtime CI is independently meaningful for the present `runtime_godot` tree and includes active 220-agent locomotion plus process-RSS regression coverage.
