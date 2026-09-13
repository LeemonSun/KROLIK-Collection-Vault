# KROLIK autonomous development state

Updated: 2026-09-14, autonomous pass 2.

## Current main / rollback

- Current coherent recovery-infrastructure commit: `626e24f45c9a3fcfdb6039ef7547da7df0b8017f`.
- Existing rollback checkpoints remain available, including `checkpoint/pre-source-restore-20260913-2356`, `checkpoint/pre-complete-source-restore-20260914-0024`, and `checkpoint/pre-source-recovery-fix-20260914-0054`.
- No application/schema contract was changed in this pass.

## Repository integrity status

The repository is still missing the stable application source (`app.py` and related source/UI/tests), so Phase A feature development must not proceed on this incomplete tree. The last `Vault CI` failure is therefore still an infrastructure/source-sync failure rather than evidence of a regression in the locally validated stable artifact.

The previous recovery attempt failed at `Restore source files`: the single binary recovery ZIP is truncated, and the legacy fallback is also not a complete ZIP. The exact stable local artifact had previously passed `python -m py_compile app.py` and `PYTHONPATH=. python -m pytest -q` with **67 passed**, but those source bytes are not currently reconstructible from the repository alone.

## Work completed in pass 2

1. Inspected latest main and the actual failed GitHub Actions job/log instead of assuming the failure reason.
2. Confirmed `tools/source_restore_parts/` exists but is not a trustworthy canonical transport set: `part_10.b64` is absent, and some staged files have anomalous sizes/alternate `.correct` fragments. Concatenating the currently canonical names cannot produce the validated stable ZIP.
3. Hardened `tools/restore_source_bundle.py` so recovery now prefers an exact canonical 11-part set (`part_00.b64` through `part_10.b64`), refuses incomplete sets, validates base64/ZIP structure and CRC before writing any tracked source, and only then considers older fallbacks.
4. Updated `Restore source bundle` workflow triggers to include `tools/source_restore_parts/**`, so a future corrected canonical part immediately invokes guarded restore + compile + tests.
5. The workflow/CI triggered after these changes; at the time this state was written those new runs were still in progress. Do not report them as passing unless a later pass confirms their conclusions.

## Tests / verification actually performed

- Inspected GitHub Actions run `34785300428` and its job log: confirmed failure occurs in `python tools/restore_source_bundle.py` with `zipfile.BadZipFile`, before source verification/commit.
- Inspected current recovery-part directory via GitHub API and confirmed the canonical set is incomplete (`part_10.b64` missing).
- New GitHub Actions runs triggered by the recovery hardening were observed **in progress**; no passing result is claimed here.
- No local Python application tests were runnable from this incomplete repository because `app.py` is absent.

## Exact blocker / safe continuation

A byte-exact copy of the validated stable source artifact (or its exact base64) is required to finish repository restoration. The current repository fragments must not be guessed/recombined because several are demonstrably incomplete or malformed. The safest continuation is:

1. If a future automation environment has the original stable ZIP mounted/available, regenerate **all 11 canonical chunks from that exact file**, replacing `part_00.b64` … `part_10.b64` as one coherent set. Do not reuse suspect staged chunks merely because their names match.
2. Let `Restore source bundle` validate ZIP CRC, restore, run `python -m py_compile app.py` and `python -m pytest -q`, and only then allow its bot commit.
3. Inspect `Vault CI` and `Godot Runtime CI` after the restore commit. Fix genuine failures before feature work.
4. Create `checkpoint/stable-source-restored-<timestamp>` once both source integrity and CI are verified; then remove/deprecate the truncated recovery artifacts.

If the original stable artifact is not available to the automation environment, do **not** stall the project by inventing replacement source. Record this same blocker and use repository-safe work only; the first run that can access the stable artifact should prioritize restoration above all roadmap work.

## Next roadmap task after integrity restoration

Return to earliest unfinished Phase A work from `docs/AUTONOMOUS_RUNBOOK.md` / `KROLIK_MASTER_PLAN.md`: prefer A1 real Godot runtime validation with actual runtime artifact if reference assets/runner permit it; otherwise take the next genuinely unblocked Phase A item (A5 clip-validation edge coverage or A4 200+ live-agent stress harness). Do not expand B–H while the foundation/CI gate is untrustworthy.
