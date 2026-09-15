from __future__ import annotations

"""Rebuild a pinned gold-character CI image from verified UTF-8 base64 parts.

The exact user PNG remains canonical through its immutable hash/dimensions in
`qa/gold/gold_elf_v1.json`. CI uses a deterministic reduced WebP derived from
that source because the pose model itself works at a reduced resolution. Every
text chunk is length/hash checked before base64 decoding, then the reconstructed
image is checked again by byte hash, dimensions and codec.
"""

import argparse
import base64
from hashlib import sha256
import json
from pathlib import Path
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SPEC = ROOT / "qa" / "gold" / "gold_elf_v1.json"
DEFAULT_OUTPUT = ROOT / ".gold_character" / "gold_elf_v1.webp"


def _load_spec(path: Path) -> dict:
    doc = json.loads(path.read_text(encoding="utf-8"))
    if doc.get("schema") != "krolik.gold-character/1":
        raise ValueError(f"unsupported gold-character schema: {doc.get('schema')!r}")
    return doc


def _verified_parts(fixture: dict) -> list[Path]:
    declared = fixture.get("parts", [])
    if not isinstance(declared, list) or not declared:
        raise ValueError("gold fixture must declare non-empty fixture.parts")

    paths: list[Path] = []
    for index, entry in enumerate(declared):
        if not isinstance(entry, dict):
            raise ValueError(f"fixture.parts[{index}] must be an object")
        rel = str(entry.get("path", "")).strip()
        if not rel:
            raise ValueError(f"fixture.parts[{index}] path is empty")
        path = ROOT / rel
        if not path.is_file():
            raise FileNotFoundError(path)
        text = path.read_text(encoding="utf-8").strip()
        expected_chars = int(entry.get("chars", -1))
        expected_sha = str(entry.get("sha256", ""))
        actual_sha = sha256(text.encode("utf-8")).hexdigest()
        if len(text) != expected_chars:
            raise ValueError(
                f"gold fixture part {rel} char-count mismatch: {len(text)} != {expected_chars}"
            )
        if actual_sha != expected_sha:
            raise ValueError(
                f"gold fixture part {rel} sha256 mismatch: {actual_sha} != {expected_sha}"
            )
        paths.append(path)

    glob_text = str(fixture.get("parts_glob", "")).strip()
    if glob_text:
        discovered = sorted(ROOT.glob(glob_text))
        if discovered != paths:
            raise ValueError(
                "gold fixture part set differs from declared ordered fixture.parts: "
                f"declared={len(paths)} discovered={len(discovered)}"
            )
    return paths


def materialize(spec_path: Path, output: Path) -> dict:
    spec = _load_spec(spec_path)
    fixture = spec["fixture"]
    parts = _verified_parts(fixture)

    encoded = "".join(path.read_text(encoding="utf-8").strip() for path in parts)
    try:
        payload = base64.b64decode(encoded, validate=True)
    except Exception as exc:  # pragma: no cover - diagnostic path
        raise ValueError(f"invalid base64 gold fixture: {exc}") from exc

    expected_bytes = int(fixture["bytes"])
    expected_sha = str(fixture["sha256"])
    actual_sha = sha256(payload).hexdigest()
    if len(payload) != expected_bytes:
        raise ValueError(f"gold fixture byte-size mismatch: {len(payload)} != {expected_bytes}")
    if actual_sha != expected_sha:
        raise ValueError(f"gold fixture sha256 mismatch: {actual_sha} != {expected_sha}")

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(payload)
    with Image.open(output) as image:
        width, height = image.size
        fmt = str(image.format or "").upper()
        image.verify()
    if width != int(fixture["width"]) or height != int(fixture["height"]):
        raise ValueError(
            f"gold fixture dimensions mismatch: {width}x{height} != "
            f"{fixture['width']}x{fixture['height']}"
        )
    if fmt != "WEBP":
        raise ValueError(f"gold fixture format mismatch: {fmt!r} != 'WEBP'")

    return {
        "id": spec["id"],
        "path": str(output.resolve()),
        "sha256": actual_sha,
        "bytes": len(payload),
        "width": width,
        "height": height,
        "format": fmt,
        "parts": len(parts),
        "original_sha256": spec["source"]["original_sha256"],
        "transform": fixture.get("transform", ""),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Materialize KROLIK gold-character regression art")
    parser.add_argument("--spec", default=str(DEFAULT_SPEC))
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--check", action="store_true", help="also remove the materialized file after verification")
    args = parser.parse_args(argv)

    try:
        result = materialize(Path(args.spec).resolve(), Path(args.output).resolve())
    except Exception as exc:
        print(f"KROLIK_GOLD_MATERIALIZE status=failed error={exc}", file=sys.stderr)
        return 1

    print(
        "KROLIK_GOLD_MATERIALIZE status=ok "
        f"id={result['id']} sha256={result['sha256']} bytes={result['bytes']} "
        f"size={result['width']}x{result['height']} format={result['format']} parts={result['parts']} "
        f"original_sha256={result['original_sha256']} path={result['path']}"
    )
    if args.check:
        Path(result["path"]).unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
