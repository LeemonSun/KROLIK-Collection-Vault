from __future__ import annotations

"""Regenerate/check portable AI policy copies from life_sim.py source of truth."""

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from ai_policy import CONTENT_POLICY_PATH, RUNTIME_POLICY_PATH, generated_policy_document


def _normalized(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail when committed copies differ from life_sim.py")
    args = parser.parse_args(argv)
    generated = generated_policy_document()
    targets = (CONTENT_POLICY_PATH, RUNTIME_POLICY_PATH)
    if args.check:
        failures = []
        for path in targets:
            try:
                current = _normalized(path)
            except Exception as exc:
                failures.append(f"{path}: {exc}")
                continue
            if current != generated:
                failures.append(f"{path}: differs from life_sim.py generated policy")
        if failures:
            for item in failures:
                print(f"FAIL {item}", file=sys.stderr)
            return 1
        print(f"KROLIK_AI_POLICY_SYNC targets={len(targets)} status=clean")
        return 0

    payload = json.dumps(generated, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    for path in targets:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(payload, encoding="utf-8")
        print(f"WROTE {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
