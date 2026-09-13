from __future__ import annotations

import argparse
import zipfile
from pathlib import Path


def restore(bundle: Path, root: Path) -> list[str]:
    root = root.resolve()
    restored: list[str] = []
    with zipfile.ZipFile(bundle, "r") as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            target = (root / info.filename).resolve()
            if root not in target.parents:
                raise ValueError(f"unsafe archive path: {info.filename}")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(info))
            restored.append(info.filename)
    return restored


def main() -> int:
    parser = argparse.ArgumentParser(description="Restore tracked KROLIK source files from the recovery bundle")
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
