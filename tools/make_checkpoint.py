from __future__ import annotations

"""Create a durable, versioned KROLIK source checkpoint.

The default checkpoint contains application source, tests, web/runtime files and
small documentation/assets, but deliberately excludes mutable collection data,
caches and nested checkpoints. Use --include-data only when you explicitly want
KROLIK_COLLECTION copied too.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time
import zipfile

DEFAULT_KEEP = 20
EXCLUDED_DIRS = {".git", ".pytest_cache", "__pycache__", "checkpoints", "KROLIK_CHECKPOINTS"}
EXCLUDED_SUFFIXES = {".pyc", ".pyo", ".tmp", ".lock"}


def _safe_label(value: str) -> str:
    cleaned = "".join(ch if ch.isalnum() or ch in "-_." else "_" for ch in value.strip())
    return cleaned.strip("._") or "manual"


def _iter_files(root: Path, include_data: bool, output_dir: Path):
    output_dir = output_dir.resolve()
    for path in sorted(root.rglob("*")):
        if path.is_dir():
            continue
        rel = path.relative_to(root)
        if any(part in EXCLUDED_DIRS for part in rel.parts):
            continue
        if not include_data and rel.parts and rel.parts[0] == "KROLIK_COLLECTION":
            continue
        if path.suffix.lower() in EXCLUDED_SUFFIXES:
            continue
        try:
            if path.resolve().is_relative_to(output_dir):
                continue
        except (OSError, ValueError):
            pass
        yield path, rel


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def create_checkpoint(root: Path, output_dir: Path, label: str, include_data: bool = False) -> tuple[Path, dict]:
    root = root.resolve()
    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d_%H%M%S")
    safe_label = _safe_label(label)
    target = output_dir / f"KROLIK_{stamp}_{safe_label}.zip"

    files = list(_iter_files(root, include_data, output_dir))
    manifest_files: list[dict] = []
    total_bytes = 0

    fd, temp_name = tempfile.mkstemp(prefix=target.name + ".", suffix=".tmp", dir=output_dir)
    os.close(fd)
    temp = Path(temp_name)
    try:
        with zipfile.ZipFile(temp, "w", zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
            for path, rel in files:
                size = path.stat().st_size
                total_bytes += size
                archive.write(path, rel.as_posix())
                manifest_files.append({"path": rel.as_posix(), "bytes": size})
            embedded = {
                "schema": "krolik.checkpoint/1",
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "label": safe_label,
                "root_name": root.name,
                "include_data": include_data,
                "file_count": len(manifest_files),
                "uncompressed_bytes": total_bytes,
                "files": manifest_files,
            }
            archive.writestr("_checkpoint_manifest.json", json.dumps(embedded, ensure_ascii=False, indent=2))
        os.replace(temp, target)
    finally:
        temp.unlink(missing_ok=True)

    metadata = {
        "schema": "krolik.checkpoint-sidecar/1",
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "label": safe_label,
        "include_data": include_data,
        "file_count": len(manifest_files),
        "uncompressed_bytes": total_bytes,
        "zip_bytes": target.stat().st_size,
        "sha256": _sha256(target),
        "archive": target.name,
    }
    target.with_suffix(".json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    (output_dir / "LATEST.txt").write_text(target.name + "\n" + metadata["sha256"] + "\n", encoding="utf-8")
    return target, metadata


def prune_checkpoints(output_dir: Path, keep: int) -> list[Path]:
    keep = max(1, int(keep))
    archives = sorted(output_dir.glob("KROLIK_*.zip"), key=lambda p: p.stat().st_mtime, reverse=True)
    removed: list[Path] = []
    for old in archives[keep:]:
        old.with_suffix(".json").unlink(missing_ok=True)
        old.unlink(missing_ok=True)
        removed.append(old)
    return removed


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a KROLIK source checkpoint")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--label", default="manual")
    parser.add_argument("--keep", type=int, default=DEFAULT_KEEP)
    parser.add_argument("--include-data", action="store_true", help="also include KROLIK_COLLECTION project data")
    args = parser.parse_args()

    root = args.root.resolve()
    output = args.output.resolve() if args.output else root.parent / "KROLIK_CHECKPOINTS"
    archive, meta = create_checkpoint(root, output, args.label, args.include_data)
    removed = prune_checkpoints(output, args.keep)
    print(f"CHECKPOINT OK: {archive}")
    print(f"SHA256: {meta['sha256']}")
    print(f"FILES: {meta['file_count']} | ZIP: {meta['zip_bytes']} bytes")
    if removed:
        print(f"PRUNED: {len(removed)} old checkpoint(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
