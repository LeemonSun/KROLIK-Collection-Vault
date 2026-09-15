#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

SCHEMA = "krolik.qa-dwpose-domain-expectations/1"
FORMAT_VERSION = 1
ALLOWED_MINIMUMS = {"dwpose-onnx", "review-fallback"}


class ExpectationError(ValueError):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ExpectationError(f"unable to read {path}: {exc}") from exc


def validate_expectations(document: Any) -> dict[str, str]:
    if not isinstance(document, dict) or document.get("schema") != SCHEMA:
        raise ExpectationError("unsupported expectations schema")
    if document.get("format_version") != FORMAT_VERSION:
        raise ExpectationError("unsupported expectations format_version")
    raw_cases = document.get("cases")
    if not isinstance(raw_cases, dict) or not raw_cases:
        raise ExpectationError("cases must be a non-empty object")
    result: dict[str, str] = {}
    for name, raw in raw_cases.items():
        if not isinstance(name, str) or not name or Path(name).name != name:
            raise ExpectationError(f"invalid case filename: {name!r}")
        if not isinstance(raw, dict):
            raise ExpectationError(f"case {name} must be an object")
        minimum = str(raw.get("minimum", ""))
        if minimum not in ALLOWED_MINIMUMS:
            raise ExpectationError(f"case {name} has invalid minimum: {minimum!r}")
        result[name] = minimum
    return result


def evaluate_report(report: Any, expectations: dict[str, str]) -> list[str]:
    if not isinstance(report, dict):
        return ["report root must be an object"]
    rows = report.get("cases")
    if not isinstance(rows, list):
        return ["report cases must be an array"]
    by_name: dict[str, dict[str, Any]] = {}
    errors: list[str] = []
    for row in rows:
        if not isinstance(row, dict):
            errors.append("report contains a non-object case")
            continue
        name = str(row.get("image", ""))
        if not name:
            errors.append("report case is missing image")
        elif name in by_name:
            errors.append(f"duplicate report case: {name}")
        else:
            by_name[name] = row
    missing = sorted(set(expectations) - set(by_name))
    extra = sorted(set(by_name) - set(expectations))
    if missing:
        errors.append("missing expected cases: " + ", ".join(missing))
    if extra:
        errors.append("unexpected report cases: " + ", ".join(extra))
    for name, minimum in expectations.items():
        row = by_name.get(name)
        if row is None:
            continue
        backend = str(row.get("backend", ""))
        runtime_ready = bool(row.get("runtime_ready"))
        review = bool(row.get("rig_review_required"))
        if not runtime_ready:
            errors.append(f"{name}: runtime_ready=false")
            continue
        if minimum == "dwpose-onnx" and backend != "dwpose-onnx":
            errors.append(f"{name}: backend regressed from dwpose-onnx to {backend or '<empty>'}")
        elif minimum == "review-fallback" and backend != "dwpose-onnx" and not review:
            errors.append(f"{name}: fallback is not explicitly review-required")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Reject per-fixture DWPose regressions hidden by aggregate coverage")
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--expectations", type=Path, required=True)
    args = parser.parse_args()
    try:
        expectations = validate_expectations(load_json(args.expectations))
        report = load_json(args.report)
        errors = evaluate_report(report, expectations)
    except ExpectationError as exc:
        print(f"KROLIK_DWPOSE_EXPECTATIONS status=failed error={exc}")
        return 2
    if errors:
        for error in errors:
            print(f"KROLIK_DWPOSE_EXPECTATION_FAIL {error}")
        return 3
    print(f"KROLIK_DWPOSE_EXPECTATIONS status=ok cases={len(expectations)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
