from __future__ import annotations

"""Regenerate/check the Godot room-library copy from validated source content."""

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from room_content import DEFAULT_ROOM_LIBRARY_PATH, validate_room_fixture_references

RUNTIME_ROOM_LIBRARY_PATH = ROOT / "runtime_godot" / "data" / "rooms_v1.json"


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)

    source = _load(DEFAULT_ROOM_LIBRARY_PATH)
    errors = validate_room_fixture_references(source)
    if errors:
        for error in errors:
            print(f"FAIL source room library: {error}", file=sys.stderr)
        return 1

    if args.check:
        try:
            runtime = _load(RUNTIME_ROOM_LIBRARY_PATH)
        except Exception as exc:
            print(f"FAIL {RUNTIME_ROOM_LIBRARY_PATH}: {exc}", file=sys.stderr)
            return 1
        if runtime != source:
            print("FAIL runtime room library differs from source content", file=sys.stderr)
            return 1
        print("KROLIK_ROOM_LIBRARY_SYNC status=clean")
        return 0

    RUNTIME_ROOM_LIBRARY_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(source, ensure_ascii=False, indent=2, sort_keys=False) + "\n"
    RUNTIME_ROOM_LIBRARY_PATH.write_text(payload, encoding="utf-8")
    print(f"WROTE {RUNTIME_ROOM_LIBRARY_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
