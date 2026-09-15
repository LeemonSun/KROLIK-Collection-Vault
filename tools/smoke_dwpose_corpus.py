from __future__ import annotations

"""Run the production KROLIK DWPose backend over a small image corpus.

This is a domain smoke, not an accuracy benchmark: there is no invented ground
truth.  Every supplied image must reach the real dwpose-onnx backend and emit a
complete portable KROLIK rig.  Per-image confidence and aggregate statistics
are printed so regressions are visible without turning confidence into a fake
accuracy claim.
"""

import argparse
import json
from pathlib import Path
from statistics import mean, median

from rig_tools import JOINT_ORDER, capabilities, detect_rig


def main() -> int:
    parser = argparse.ArgumentParser(description="Require production DWPose on every image in a corpus")
    parser.add_argument("images", nargs="+")
    parser.add_argument("--min-confidence", type=float, default=0.12)
    parser.add_argument("--report", default="")
    args = parser.parse_args()

    caps = capabilities()
    if not caps.get("dwpose"):
        print(f"KROLIK_DWPOSE_CORPUS status=failed error=dwpose_capability_unavailable caps={caps}")
        return 2

    rows: list[dict[str, object]] = []
    failed = 0
    for raw in args.images:
        image = Path(raw).resolve()
        if not image.is_file():
            rows.append({"image": str(image), "status": "missing"})
            failed += 1
            continue
        detection = detect_rig(image, prefer_ai=True)
        backend = str(detection.settings.get("backend") or "")
        confidence = float(detection.settings.get("pose_confidence", 0.0))
        missing = [name for name in JOINT_ORDER if name not in detection.joints]
        in_bounds = True
        for name in JOINT_ORDER:
            point = detection.joints.get(name, {})
            try:
                x = float(point.get("x", -1.0))
                y = float(point.get("y", -1.0))
            except Exception:
                in_bounds = False
                break
            if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
                in_bounds = False
                break
        ok = backend == "dwpose-onnx" and not missing and in_bounds and confidence >= args.min_confidence
        if not ok:
            failed += 1
        row = {
            "image": image.name,
            "status": "ok" if ok else "failed",
            "backend": backend,
            "confidence": round(confidence, 6),
            "joints": len(detection.joints),
            "missing": missing,
            "in_bounds": in_bounds,
        }
        rows.append(row)
        print("KROLIK_DWPOSE_CORPUS_CASE " + json.dumps(row, separators=(",", ":"), sort_keys=True))

    confidences = [float(row["confidence"]) for row in rows if row.get("backend") == "dwpose-onnx"]
    report = {
        "schema": "krolik.dwpose-domain-smoke/1",
        "samples": len(rows),
        "passed": len(rows) - failed,
        "failed": failed,
        "min_required_confidence": args.min_confidence,
        "mean_confidence": round(mean(confidences), 6) if confidences else 0.0,
        "median_confidence": round(median(confidences), 6) if confidences else 0.0,
        "min_confidence": round(min(confidences), 6) if confidences else 0.0,
        "max_confidence": round(max(confidences), 6) if confidences else 0.0,
        "cases": rows,
    }
    if args.report:
        report_path = Path(args.report).resolve()
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print("KROLIK_DWPOSE_CORPUS " + " ".join(f"{key}={value}" for key, value in report.items() if key != "cases"))
    return 0 if failed == 0 else 3


if __name__ == "__main__":
    raise SystemExit(main())
