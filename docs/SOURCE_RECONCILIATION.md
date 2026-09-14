# KROLIK Canonical Source Reconciliation

## Why this file exists

The repository contains a modern, verified runtime/core development line, but the historical graphical/backend application source is not currently canonical in Git.

An external snapshot named `KROLIK_Collection_Vault_FULL_2026-09-13_2158.zip` is independently known to have contained a healthy substantial `app.py`. That exact snapshot is currently outside the repository/session. Historical Git recovery transports are damaged or incomplete and must not be used to guess source bytes.

This document is the required reconciliation procedure. Future autonomous runs should follow it instead of retrying ad-hoc recovery combinations.

## Current facts

Current Git `main` has no `app.py`.

Known in-repository recovery candidates were audited non-destructively:

| Candidate | Result |
| --- | --- |
| `tools/source_restore.zip` | Not a valid ZIP. SHA-256 `1a3a8ec920980f842b3032a875a71bf2dd6d9d5807d77a85829ff8ab6b6da869`. |
| canonical `part_00..part_10.b64` | Incomplete canonical set. |
| historical original `part_07` combination | Invalid base64 transport. |
| historical `part_07.correct` combination | Valid ZIP containing `app.py`, but `app.py` fails CRC. Payload SHA-256 `057cacf29919636b0ec66ed82ea9fa16dd524fd928d68cb9b6df5c49f715bfdc`. |
| legacy `.source_sync` chunks | Not a valid ZIP. SHA-256 `948dcb40911ff5687b8c7f28efe39f9a6beea31fc7f9c0a7c66a979a55e7c180`. |

`tools/audit_source_readiness.py` is the canonical read-only checker for this state.

Expected current result:

```text
KROLIK_SOURCE_READINESS status=blocked app_present=false recoverable=false
```

## Never do this

Do not:
- infer or repair missing `app.py` bytes by hand;
- concatenate arbitrary recovery chunks until a ZIP happens to open;
- accept a ZIP that opens but fails CRC;
- overwrite modern runtime/core files from an old snapshot wholesale;
- call backend/UI verified merely because core/runtime CI is green;
- force-push an old full-project snapshot over modern `main`.

## Safe reconciliation procedure when the FULL ZIP becomes available

### 1. Preserve the external source exactly

Treat the uploaded FULL ZIP as immutable evidence.

Record:
- file name;
- byte size;
- SHA-256;
- ZIP member list;
- per-member CRC result.

Reject the archive if ZIP structure is invalid or any required member fails CRC.

### 2. Extract only into an isolated workspace

Before writing any member:
- reject absolute paths;
- reject `..` path traversal;
- reject paths resolving outside the extraction root;
- never extract directly over `main`.

Use a dedicated integration branch based on the latest verified `main`.

### 3. Classify every recovered file

For every file in the external snapshot, classify it as one of:

- **missing in current Git** — candidate for exact transplant;
- **identical** — no action;
- **snapshot-only old implementation** — preserve only if required by the recovered backend/UI;
- **modern Git is newer** — do not overwrite automatically;
- **true conflict** — review at code/contract level before merging.

`app.py` is currently in the first category: missing in current Git.

### 4. Preserve modern contracts

Do not regress the current verified work in:
- rig migrations;
- animation content/validation;
- fixture/pose content;
- Godot deformation;
- IK/layering/secondary motion/facial state;
- generated AI policy;
- personality;
- short-term memory;
- stress instrumentation.

If the historical backend expects an older API, adapt the backend/integration boundary rather than rolling back modern runtime contracts silently.

### 5. Restore application/backend/UI source

Transplant the exact healthy `app.py` and other missing backend/UI files from the authoritative snapshot.

Review old snapshot versions of shared modules (`runtime_package.py`, `rig_tools.py`, etc.) before copying them. Prefer preserving modern versions and porting only missing APIs unless an exact diff proves otherwise.

### 6. Restore full verification

On the integration branch run, at minimum:

```text
python -m py_compile app.py
pytest
python tests/http_smoke.py
python tests/ui_mock_smoke.py
```

Also run current:
- AI policy sync;
- content validator;
- core Python regression suite;
- Godot project import/runtime smoke;
- motion/IK/facial/secondary regressions;
- rendered deformation regression;
- 220-agent stress.

Backend/UI being green must no longer rely on `SKIPPED`.

### 7. Prove one end-to-end product path

After source reconciliation, priority shifts to one vertical slice:

1. launch app;
2. import one real character image;
3. produce cutout;
4. produce/detect rig;
5. allow correction;
6. build skin/runtime package;
7. launch character in Godot runtime;
8. visibly animate/navigate;
9. save character/world state;
10. restart and reload successfully.

Do not resume deep D4/D5 AI expansion before this vertical slice is working unless a human explicitly reprioritizes.

## CI meaning after source audit hardening

`Vault CI: success` can mean the **core + source audit** are healthy even while the full application source is blocked.

The job summary must explicitly distinguish:
- `FULL SOURCE AVAILABLE` — backend/UI tests run;
- `FULL PRODUCT SOURCE BLOCKED` — backend/UI is not verified.

This prevents a skipped backend/UI job from being misread as product readiness.

## Current safe continuation when the ZIP is unavailable

If the authoritative FULL ZIP is unavailable:

- do not retry damaged recovery candidates endlessly;
- do not continue adding AI depth merely because it is easy to work on;
- prefer source-independent work that directly supports the end-to-end vertical slice, A2 pose-model validation, or Windows performance validation;
- keep D4 work preserved on its recovery branch but paused;
- keep `docs/AUTONOMOUS_STATE.md` accurate after every substantive pass.
