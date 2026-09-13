from __future__ import annotations

import argparse
import base64
import binascii
import io
import zipfile
from pathlib import Path


RECOVERY_PART_DIR = "tools/source_restore_parts"
EXPECTED_RECOVERY_PARTS = 11
LEGACY_CHUNKS = (
    ".source_sync/part_000.txt",
    ".source_sync/part_001.txt",
    ".source_sync/part_002.txt",
    ".source_sync_missing/missing_003a.txt",
    ".source_sync/part_003.txt",
)


def _decode_zip_payload(raw: bytes, source: str) -> bytes:
    if raw.startswith(b"PK"):
        payload = raw
    else:
        compact = b"".join(raw.split())
        try:
            payload = base64.b64decode(compact, validate=True)
        except (binascii.Error, ValueError) as exc:
            raise zipfile.BadZipFile(
                f"{source} is neither a ZIP file nor valid base64 ZIP data"
            ) from exc
    if not payload.startswith(b"PK"):
        raise zipfile.BadZipFile(f"decoded {source} has no ZIP signature")
    with zipfile.ZipFile(io.BytesIO(payload), "r") as archive:
        archive.infolist()
        bad = archive.testzip()
        if bad is not None:
            raise zipfile.BadZipFile(f"CRC failure in {source}: {bad}")
    return payload


def _numbered_parts_payload(root: Path) -> tuple[bytes, str] | None:
    """Load only a complete, canonical numbered recovery set.

    Recovery data crosses text-oriented connector transports. Partial/duplicated
    chunks must never be guessed into a ZIP: accepting them risks overwriting a
    stable tree with corrupted source. A canonical bundle is exactly part_00
    through part_10; helper/corrected fragments are ignored until promoted to
    their canonical filename.
    """
    directory = root / RECOVERY_PART_DIR
    if not directory.is_dir():
        return None
    expected = [directory / f"part_{index:02d}.b64" for index in range(EXPECTED_RECOVERY_PARTS)]
    missing = [path.name for path in expected if not path.is_file() or path.stat().st_size == 0]
    if missing:
        raise zipfile.BadZipFile(
            "incomplete canonical recovery part set; missing: " + ", ".join(missing)
        )
    raw = b"".join(path.read_bytes().strip() for path in expected)
    label = f"{RECOVERY_PART_DIR}/part_00..part_{EXPECTED_RECOVERY_PARTS - 1:02d}.b64"
    return _decode_zip_payload(raw, label), label


def _bundle_payload(bundle: Path, root: Path) -> tuple[bytes, str]:
    # Prefer the canonical text-safe transport once it is complete. This avoids
    # ever selecting the known-truncated binary artifact by accident.
    try:
        numbered = _numbered_parts_payload(root)
        if numbered is not None:
            return numbered
    except zipfile.BadZipFile as parts_error:
        print(f"numbered recovery parts rejected: {parts_error}")

    if bundle.exists():
        try:
            return _decode_zip_payload(bundle.read_bytes(), str(bundle)), str(bundle)
        except zipfile.BadZipFile as primary_error:
            print(f"primary recovery bundle rejected: {primary_error}")

    chunks: list[bytes] = []
    used: list[str] = []
    for relative in LEGACY_CHUNKS:
        path = root / relative
        if not path.exists() or path.stat().st_size == 0:
            continue
        chunks.append(path.read_bytes().strip())
        used.append(relative)
    if not chunks:
        raise zipfile.BadZipFile("no usable recovery bundle or legacy chunks found")
    combined = b"".join(chunks)
    label = "+".join(used)
    return _decode_zip_payload(combined, label), label


def restore(bundle: Path, root: Path) -> list[str]:
    root = root.resolve()
    restored: list[str] = []
    payload, source = _bundle_payload(bundle, root)
    print(f"using recovery source: {source}")
    with zipfile.ZipFile(io.BytesIO(payload), "r") as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            target = (root / info.filename).resolve()
            if target == root or root not in target.parents:
                raise ValueError(f"unsafe archive path: {info.filename}")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(info))
            restored.append(info.filename)
    return restored


def main() -> int:
    parser = argparse.ArgumentParser(description="Restore tracked KROLIK source files from recovery data")
    parser.add_argument("--bundle", default="tools/source_restore.zip")
    parser.add_argument("--root", default=".")
    args = parser.parse_args()
    root = Path(args.root)
    restored = restore(Path(args.bundle), root)
    print(f"restored {len(restored)} files")
    for path in restored:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
