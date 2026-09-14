# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 6.

## Current main / rollback

- Runtime/CI implementation commit: `b0cc4200ed856cb0f52f56c54ce7537bc4edb35f` (`Measure Godot stress RSS in CI`).
- Pre-change rollback checkpoint: `checkpoint/pre-stress-rss-20260914-0558` at `2381eecd31feafdf16f7b379533fadd2d29209c0`.
- No application/schema/data contract changed in this pass.

## Repository integrity status

The validated Python/editor application source (`app.py` and related UI/tests) is still absent, so Python application feature work remains blocked. The canonical recovery transport remains incomplete (`tools/source_restore_parts/part_10.b64` absent); never guess missing source bytes. Vault CI's source-integrity gate remains intentional until restoration.

The Godot runtime tree is independently present and testable, so this pass continued Phase A/A4 runtime performance verification.

## Work completed in pass 6

1. Hardened `.github/workflows/godot-runtime.yml` so the existing 220-agent active-locomotion stress run is wrapped by GNU `/usr/bin/time -v` and records runner-level **maximum resident set size (RSS)** for the actual Godot process tree invocation.
2. Added machine-readable `KROLIK_STRESS_PROCESS max_rss_kb/max_rss_mib/budget_kb` telemetry.
3. Added a deliberately conservative 512 MiB (`524288 KiB`) RSS regression ceiling. This is a CI guardrail, not a final production memory target; it is intentionally loose until repeated samples and Windows measurements establish a tighter baseline.
4. Preserved the stress harness's existing locomotion assertions and exit status. The workflow now fails if RSS cannot be parsed, if the budget is exceeded, or if the Godot harness itself fails.
5. Created rollback checkpoint `checkpoint/pre-stress-rss-20260914-0558` before the workflow change.

## Tests / verification actually performed

At state-write time, GitHub Actions `Godot Runtime CI` run `34801002793`, job `103843504016`, for commit `b0cc4200ed856cb0f52f56c54ce7537bc4edb35f` had started and was still **in progress**. Checkout succeeded and the verified-Godot download step was running; parse/import, runtime smoke, and the new RSS-instrumented 220-agent stress step had not yet completed. Therefore this pass does **not** claim the new memory guard as verified yet.

The immediately preceding verified baseline remains Godot Runtime CI run `34797585790`: Godot 4.7.2 import + runtime smoke + active 220-agent locomotion stress succeeded with `agents=220 active=220 frames=180 seconds=4.9003 avg_fps=36.73 moving=220 moved=220 moved_share=1.000 avg_travel=222.19`.

No Python application tests were run because the validated Python/editor source remains absent. A green Vault CI in this recovery state is source-integrity status only, not backend/UI coverage.

## Exact blockers / safe continuation

Primary restoration blocker remains a byte-exact copy of the validated stable Python/editor source artifact (or complete exact base64 transport). Do not reconstruct it by guessing.

Next pass should:

1. Inspect Godot Runtime CI run `34801002793` first. If it failed, repair the RSS wrapper/parser/budget before any new work. If it succeeded, record the measured maximum RSS and treat it as the first Linux/headless active-agent memory baseline.
2. If source is still unavailable after that, pursue A1 visual deformation verification using repository-contained synthetic/reference assets if feasible. Prefer a deterministic headless render/screenshot or image-difference proof that actual Skeleton2D/Polygon2D deformation changes pixels, not string-only assertions.
3. Do not call A4 complete until rendered Windows FPS/CPU/memory is measured. The Linux/headless CI is a regression baseline only; tighten the 512 MiB budget only after enough stable samples exist.

## CI semantics until restoration

`Vault CI` distinguishes repository/source integrity from application verification. While `app.py` is absent, green Vault CI means only that recovery state was detected correctly. Godot Runtime CI is independently meaningful for the present `runtime_godot` tree and includes active 220-agent locomotion coverage; pass 6 adds process-RSS instrumentation pending CI completion.
