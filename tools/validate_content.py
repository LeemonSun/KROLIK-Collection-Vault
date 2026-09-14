from __future__ import annotations

"""Validate data-driven KROLIK content packs without launching the editor."""

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from animation_content import ANIMATION_SCHEMA, validate_animation_document
from prop_content import FIXTURE_SCHEMA, validate_fixture_document


def validate_file(path: Path) -> list[str]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [f"unable to parse JSON: {exc}"]
    schema = document.get("schema") if isinstance(document, dict) else None
    if schema == ANIMATION_SCHEMA:
        return validate_animation_document(document)
    if schema == FIXTURE_SCHEMA:
        return validate_fixture_document(document)
    # Path hints keep diagnostics useful for malformed files whose schema field
    # itself is missing/wrong, while the validator still reports the schema.
    if "animations" in path.parts:
        return validate_animation_document(document)
    if "fixtures" in path.parts:
        return validate_fixture_document(document)
    return [f"unsupported content schema {schema!r}"]


def iter_content_files(root: Path) -> list[Path]:
    if not root.exists():
        return []
    return sorted(path for path in root.rglob("*.json") if path.is_file())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate KROLIK data-driven content JSON")
    parser.add_argument("paths", nargs="*", help="Files/directories; defaults to ./content")
    args = parser.parse_args(argv)

    requested = [Path(item).resolve() for item in args.paths] if args.paths else [ROOT / "content"]
    files: list[Path] = []
    for path in requested:
        if path.is_dir():
            files.extend(iter_content_files(path))
        elif path.is_file():
            files.append(path)
        else:
            print(f"ERROR {path}: not found", file=sys.stderr)
            return 2
    files = sorted(set(files))
    if not files:
        print("ERROR: no content JSON files found", file=sys.stderr)
        return 2

    failures = 0
    for path in files:
        errors = validate_file(path)
        rel = path
        try:
            rel = path.relative_to(ROOT)
        except ValueError:
            pass
        if errors:
            failures += 1
            print(f"FAIL {rel}")
            for error in errors:
                print(f"  - {error}")
        else:
            print(f"PASS {rel}")
    print(f"KROLIK_CONTENT_VALIDATION files={len(files)} failed={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
