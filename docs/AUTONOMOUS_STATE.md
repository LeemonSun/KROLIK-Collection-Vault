# AUTONOMOUS STATE

Last updated: 2026-09-14 23:00 +03:00

## Current repository state

Latest main observed during this run: `421f9c1932b151229fc7d73fabe77d124bfefb19`. This includes this run's import-integrity implementation through parent `776b18f3f7bf01ea605fe9e04a8fce5767048855` plus a concurrent Windows packaging fix.

Rollback checkpoint created before the integrity block: `checkpoint/pre-import-validation-20260914-2255` at `d7e1e62078a7ee93097a9d077d3207291803dbd6`.

No rig/skin/animation/runtime-character/AI-policy/asset-import contract changed.

## This run — durable import integrity gate

Added `import_integrity.py` as a non-destructive verifier for existing `krolik.asset-import/1` receipts. It streams SHA-256 verification for immutable originals and derived cutouts, validates receipt schema/version and required files, and cross-checks build-result identity against the durable receipt.

`tools/import_character_package.py` now performs this integrity gate after package build, returns exit code 3 on integrity failure, and emits `KROLIK_CHARACTER_IMPORT_INTEGRITY` evidence on success/failure.

Added `tests/test_import_integrity.py` with four regressions: untouched asset acceptance, immutable-original tamper detection, derived-cutout tamper detection, and forged build-result/receipt mismatch. Vault CI syntax/test allowlists include the new module/tests.

This adds no per-agent runtime cost and does not mutate originals.

## Validation actually observed

Vault CI run `34889954378` for implementation commit `776b18f3f7bf01ea605fe9e04a8fce5767048855` started successfully. At the last observation it was still IN PROGRESS, so no passing result is claimed. Checkout passed; setup/core regression steps were still running/pending. No local Python/Godot execution environment was available through this connector.

A concurrent main commit `421f9c1932b151229fc7d73fabe77d124bfefb19` changed Windows PyInstaller data bundling after the integrity commit. Inspect CI for the newest main before creating any stable checkpoint.

## Existing verified baseline

Prior verified baseline includes ordinary-image import, immutable originals, derived cutout modes, heuristic rig fallback, versioned manual joint correction, runtime package export, production Godot GPU skin/collision/AI movement, multi-format import QA, rendered deformation, and 220-agent Linux stress. D1 AI-policy sync, D2 personality and D3 bounded short-term memory remain verified. D4 affinity stays paused.

## Blockers / unverified

- Canonical `app.py` remains absent. Never synthesize it from damaged recovery artifacts; reconcile the authoritative external `KROLIK_Collection_Vault_FULL_2026-09-13_2158.zip` when available.
- Backend/UI remains source-blocked and unverified.
- A2 real DWPose/RTMPose accuracy remains blocked on a validated ONNX model.
- Final rendered Windows 200–500-agent performance remains unmeasured.
- `KROLIK_MASTER_PLAN.md` is absent; use `docs/AUTONOMOUS_RUNBOOK.md`.
- Busy-background matting remains conservative/review-required rather than destructive.

## Next highest-priority task

First inspect the newest Vault/Windows/Godot CI after `421f9c1932b151229fc7d73fabe77d124bfefb19`. Repair failures before expanding work. If green, create a stable checkpoint for the coherent import/Windows block. If canonical source is still unavailable, continue the same vertical path by adding durable reopen/reload validation for an existing imported package, including receipt integrity plus runtime manifest/image hash/schema validation before reuse. Keep D4/D5 paused.
