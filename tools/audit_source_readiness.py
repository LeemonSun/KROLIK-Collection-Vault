from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import io
import json
import zipfile
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class CandidateResult:
    name: str
    available: bool
    valid_zip: bool
    app_present: bool
    app_crc_ok: bool
    sha256: str = ""
    detail: str = ""


@dataclass(frozen=True)
class SourceReadiness:
    status: str
    app_present: bool
    recoverable: bool
    candidates: tuple[CandidateResult, ...]
    action: str


def _decode_candidate(raw: bytes, name: str) -> CandidateResult:
    if not raw:
        return CandidateResult(name, False, False, False, False, detail="empty")
    payload = raw
    if not raw.startswith(b"PK"):
        compact = b"".join(raw.split())
        try:
            payload = base64.b64decode(compact, validate=True)
        except (binascii.Error, ValueError) as exc:
            return CandidateResult(
                name, True, False, False, False,
                detail=f"invalid base64/zip transport: {exc}",
            )
    digest = hashlib.sha256(payload).hexdigest()
    if not payload.startswith(b"PK"):
        return CandidateResult(
            name, True, False, False, False, digest,
            "decoded payload has no ZIP signature",
        )
    try:
        with zipfile.ZipFile(io.BytesIO(payload), "r") as archive:
            names = {info.filename for info in archive.infolist() if not info.is_dir()}
            app_present = "app.py" in names
            bad = archive.testzip()
            if bad is not None:
                return CandidateResult(
                    name, True, True, app_present, bad != "app.py", digest,
                    f"CRC failure: {bad}",
                )
            return CandidateResult(
                name, True, True, app_present, app_present, digest,
                "archive CRC clean" if app_present else "archive clean but app.py absent",
            )
    except zipfile.BadZipFile as exc:
        return CandidateResult(name, True, False, False, False, digest, str(exc))


def _read_joined(paths: list[Path]) -> bytes | None:
    if not paths or any(not path.is_file() or path.stat().st_size == 0 for path in paths):
        return None
    return b"".join(path.read_bytes().strip() for path in paths)


def audit(root: Path) -> SourceReadiness:
    root = root.resolve()
    app = root / "app.py"
    if app.is_file() and app.stat().st_size > 0:
        return SourceReadiness(
            status="present",
            app_present=True,
            recoverable=True,
            candidates=(),
            action="Run backend/UI validation; app.py is present.",
        )

    candidates: list[CandidateResult] = []

    binary = root / "tools" / "source_restore.zip"
    candidates.append(
        _decode_candidate(binary.read_bytes(), "tools/source_restore.zip")
        if binary.is_file()
        else CandidateResult("tools/source_restore.zip", False, False, False, False, detail="missing")
    )

    part_dir = root / "tools" / "source_restore_parts"
    canonical = [part_dir / f"part_{index:02d}.b64" for index in range(11)]
    canonical_raw = _read_joined(canonical)
    candidates.append(
        _decode_candidate(canonical_raw, "canonical part_00..part_10")
        if canonical_raw is not None
        else CandidateResult(
            "canonical part_00..part_10", False, False, False, False,
            detail="incomplete canonical part set",
        )
    )

    # Historical exact variants are audited only; they are never used to restore.
    prefix = [part_dir / f"part_{index:02d}.b64" for index in range(7)]
    suffix = [part_dir / "part_08.b64", part_dir / "part_09.b64"]
    for seventh in (part_dir / "part_07.b64", part_dir / "part_07.correct.b64"):
        paths = [*prefix, seventh, *suffix]
        raw = _read_joined(paths)
        label = f"historical {'corrected' if seventh.name == 'part_07.correct.b64' else 'original'} part_07"
        candidates.append(
            _decode_candidate(raw, label)
            if raw is not None
            else CandidateResult(label, False, False, False, False, detail="missing historical part")
        )

    legacy_paths = [
        root / ".source_sync" / "part_000.txt",
        root / ".source_sync" / "part_001.txt",
        root / ".source_sync" / "part_002.txt",
        root / ".source_sync_missing" / "missing_003a.txt",
        root / ".source_sync" / "part_003.txt",
    ]
    legacy_raw = b"".join(
        path.read_bytes().strip()
        for path in legacy_paths
        if path.is_file() and path.stat().st_size > 0
    )
    candidates.append(
        _decode_candidate(legacy_raw, "legacy .source_sync chunks")
        if legacy_raw
        else CandidateResult("legacy .source_sync chunks", False, False, False, False, detail="missing")
    )

    recoverable = any(
        item.available and item.valid_zip and item.app_present and item.app_crc_ok
        for item in candidates
    )
    return SourceReadiness(
        status="recoverable" if recoverable else "blocked",
        app_present=False,
        recoverable=recoverable,
        candidates=tuple(candidates),
        action=(
            "Use only the CRC-clean recovery candidate and verify it before writing files."
            if recoverable
            else "Provide the authoritative FULL source snapshot containing app.py; do not reconstruct corrupted bytes."
        ),
    )


def _print_human(result: SourceReadiness) -> None:
    print(
        f"KROLIK_SOURCE_READINESS status={result.status} "
        f"app_present={str(result.app_present).lower()} recoverable={str(result.recoverable).lower()}"
    )
    for item in result.candidates:
        print(
            "KROLIK_SOURCE_CANDIDATE "
            f"name={json.dumps(item.name)} available={str(item.available).lower()} "
            f"valid_zip={str(item.valid_zip).lower()} app_present={str(item.app_present).lower()} "
            f"app_crc_ok={str(item.app_crc_ok).lower()} sha256={item.sha256 or '-'} "
            f"detail={json.dumps(item.detail)}"
        )
    print(f"KROLIK_SOURCE_ACTION {result.action}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit KROLIK canonical application-source readiness without modifying files")
    parser.add_argument("--root", default=".")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--require-canonical", action="store_true")
    args = parser.parse_args()

    result = audit(Path(args.root))
    if args.json:
        payload = asdict(result)
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    else:
        _print_human(result)

    if args.require_canonical and result.status != "present":
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
