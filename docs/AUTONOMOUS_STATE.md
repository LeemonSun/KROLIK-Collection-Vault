# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 15.

## Current main / rollback

- Current runtime/CI implementation commit: `b9b10222a07f7f1128b58850e12ef36a78f2c61d` (`Fix stress command exit capture under Actions shell`).
- Rollback checkpoint created before this change: `checkpoint/pre-stress-time-exit-fix-20260914` at `3192ec64e17befc198c92b029b13a3650f61101d`.
- Earlier rollback checkpoints remain available.
- No application/schema/data contract changed in this pass.

## Repository integrity status

The validated Python/editor application source (`app.py` and related UI/tests) is still absent, so Python application feature work remains blocked. The canonical recovery transport remains incomplete (`tools/source_restore_parts/part_10.b64` absent); never guess missing source bytes. Vault CI's source-integrity gate remains intentional until restoration.

The Godot runtime tree is independently present and testable.

`KROLIK_MASTER_PLAN.md` remains unavailable at the expected root/docs locations; use the phase order preserved in `docs/AUTONOMOUS_RUNBOOK.md` until the roadmap file is restored/found.

## Work completed in pass 15

1. Read `docs/AUTONOMOUS_RUNBOOK.md`, previous state and the latest CI before editing.
2. Inspected Godot Runtime CI run `34837762333`: project import and ordinary headless runtime smoke succeeded; only the 220-agent stress/RSS step failed.
3. Downloaded the actual failed job log. It proved the shell exited immediately after `/usr/bin/time ... Godot` with exit code 4, before `stress_status=$?`, `cat`, RSS parsing or diagnostics executed. GitHub Actions invokes the Bash step with an outer `-e`, so the previous `set -uo pipefail` did not reliably neutralize errexit for the simple failing command.
4. Created rollback checkpoint `checkpoint/pre-stress-time-exit-fix-20260914`.
5. Changed only the CI wrapper: the measured `/usr/bin/time -> timeout -> Godot` command now runs as the condition of an `if`, where Bash errexit is suppressed by language semantics, and captures the exact status in the `else`. Harness assertions, 90-second watchdog and 512 MiB RSS gate are unchanged.
6. Pushed implementation commit `b9b10222a07f7f1128b58850e12ef36a78f2c61d` to `main`.

## Tests / verification actually performed

- Godot Runtime CI `34837762333` for prior commit `3192ec64e17befc198c92b029b13a3650f61101d`: **failure**. Download/import: success. Ordinary headless runtime smoke: success. Stress step: failure with process exit code 4 before post-command diagnostics.
- No local Python/Godot tests were run: this connector provides repository/Actions access, not a local executable checkout, and validated Python/editor source remains absent.
- New Actions run for implementation `b9b10222a07f7f1128b58850e12ef36a78f2c61d` was not yet visible immediately after push; do not claim it passed.

## Anything still unverified

- The actual Godot stress harness exit reason behind status 4; the new wrapper is intended to expose its captured stdout/stderr and RSS instead of losing them to shell errexit.
- Whether the new implementation passes the 220-agent harness/RSS gates.
- Exact Linux/headless RSS/FPS baseline from a verified green run.
- Rendered/Windows performance remains unmeasured, so A4 is not complete.

## Exact blockers / safe continuation

Primary restoration blocker remains a byte-exact copy of the validated stable Python/editor source artifact (or complete exact base64 transport). Do not reconstruct it by guessing.

Roadmap-document blocker: `KROLIK_MASTER_PLAN.md` is not discoverable at expected paths. Do not recreate it from guesses; use the preserved runbook phase order.

Next pass should:

1. Inspect the Godot Runtime CI triggered by `b9b10222a07f7f1128b58850e12ef36a78f2c61d`. If red, read the job log: the wrapper should now expose Godot output, `/usr/bin/time`, `KROLIK_STRESS_PROCESS_STATUS`, and the tail before failing. Fix the actual harness/runtime cause without weakening assertions/budgets.
2. Once stress CI is green, create/update a stable checkpoint and immediately continue substantive A1: deterministic proof that `VaultSkinnedCharacter`/`Skeleton2D`/`Polygon2D` bone transforms produce actual mesh deformation, followed by rendered/pixel evidence when CI-safe rendering is available.
3. Do not call A4 complete until rendered Windows FPS/CPU/memory is measured. Linux/headless CI remains a regression baseline only.

## CI semantics until restoration

`Vault CI` distinguishes repository/source integrity from application verification. While `app.py` is absent, green Vault CI means only that recovery state was detected correctly. Godot Runtime CI is independently meaningful for the present `runtime_godot` tree and includes active 220-agent locomotion plus process-RSS regression coverage.
