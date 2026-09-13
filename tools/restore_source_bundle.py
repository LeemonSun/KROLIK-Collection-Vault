from __future__ import annotations

import argparse
import base64
import binascii
import io
import zipfile
from pathlib import Path


def _bundle_payload(bundle: Path) -> bytes:
    """Return ZIP bytes from either a binary ZIP or a text/base64 recovery blob.

    GitHub connector transports may preserve uploaded base64 as text rather than
    decoding it to binary. Supporting both representations keeps the recovery
    path deterministic and makes the bundle portable through text-only tools.
    """
    raw = bundle.read_bytes()
    if raw.startswith(b"PK"):
        return raw

    compact = b"".join(raw.split())
    try:
        decoded = base64.b64decode(compact, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise zipfile.BadZipFile(
            f"{bundle} is neither a ZIP file nor valid base64 ZIP data"
        ) from exc
    if not decoded.startswith(b"PK"):
        raise zipfile.BadZipFile(
            f"decoded {bundle} does not contain a ZIP signature"
        )
    return decoded


def restore(bundle: Path, root: Path) -> list[str]:
    root = root.resolve()
    restored: list[str] = []
    payload = _bundle_payload(bundle)
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
    parser = argparse.ArgumentParser(
        description="Restore tracked KROLIK source files from the recovery bundle"
    )
    parser.add_argument("--bundle", default="tools/source_restore.zip")
    parser.add_argument("--root", default=".")
    args = parser.parse_args()
    restored = restore(Path(args.bundle), Path(args.root))
    print(f"restored {len(restored)} files")
    for path in restored:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
