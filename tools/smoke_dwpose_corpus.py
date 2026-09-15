from __future__ import annotations

"""Run the production KROLIK import/auto-rig path over a small art corpus.

This is a domain smoke, not an accuracy benchmark.  Each source image goes
through immutable import, derived cutout, auto-rig, skin/collision generation
and runtime-package creation.  A stylized art sample may legitimately fall back
to the deterministic heuristic, but that fallback must be explicitly marked for
manual rig review; it must never silently masquerade as an accepted AI rig.

The corpus therefore gates two different product properties:
1. every sample must produce a runtime-ready package;
2. DWPose must cover at least the configured share of the corpus, while all
   remaining fallback samples are explicitly reviewable.
"""

import argparse
import json
from pathlib import Path
from statistics import mean, median
import tempfile

from character_import import build_character_runtime_package
from rig_tools import capabilities


def main() -> int:
    parser = argparse.ArgumentParser(description="Gate the production KROLIK auto-rig path on an art corpus")
    parser.add_argument("images", nargs="+")
    parser.add_argument("--min-dwpose-share", type=float, default=0.75)
    parser.add_argument("--report", default="")
    args = parser.parse_args()

    min_share = max(0.0, min(1.0, float(args.min_dwpose_share)))
    caps = capabilities()
    if not caps.get("dwpose"):
        print(f"KROLIK_DWPOSE_CORPUS status=failed error=dwpose_capability_unavailable caps={caps}")
        return 2

    rows: list[dict[str, object]] = []
    failed_runtime = 0
    unsafe_fallbacks = 0
    dwpose_count = 0

    with tempfile.TemporaryDirectory(prefix="krolik-dwpose-domain-") as tmp:
        project_root = Path(tmp)
        for index, raw in enumerate(args.images):
            image = Path(raw).resolve()
            if not image.is_file():
                rows.append({"image": str(image), "status": "missing"})
                failed_runtime += 1
                continue

            package = build_character_runtime_package(
                project_root,
                image,
                f"domain-{index}",
                name=f"Domain {index}",
                cutout_mode="auto",
                prefer_ai_rig=True,
            )
            backend = str(package.get("backend") or "")
            runtime_ready = bool(package.get("runtime_ready"))
            rig_review_required = bool(package.get("rig_review_required"))
            if backend == "dwpose-onnx":
                dwpose_count += 1
            fallback_safe = backend == "dwpose-onnx" or rig_review_required
            if not runtime_ready:
                failed_runtime += 1
            if not fallback_safe:
                unsafe_fallbacks += 1

            row = {
                "image": image.name,
                "status": "ok" if runtime_ready and fallback_safe else "failed",
                "backend": backend,
                "rig_review_required": rig_review_required,
                "runtime_ready": runtime_ready,
                "rig_score": round(float(package.get("rig_score", 0.0)), 4),
                "joints": int(package.get("joints", 0)),
                "bones": int(package.get("bones", 0)),
                "collision_proxies": int(package.get("collision_proxies", 0)),
                "cutout_method": str(package.get("cutout_method") or ""),
                "cutout_confidence": round(float(package.get("cutout_confidence", 0.0)), 6),
                "cutout_review_required": bool(package.get("review_required")),
                "alpha_coverage": round(float(package.get("alpha_coverage", 0.0)), 6),
            }
            rows.append(row)
            print("KROLIK_DWPOSE_CORPUS_CASE " + json.dumps(row, separators=(",", ":"), sort_keys=True))

    sample_count = len(rows)
    dwpose_share = dwpose_count / max(1, sample_count)
    scores = [float(row.get("rig_score", 0.0)) for row in rows if row.get("status") != "missing"]
    coverage_ok = dwpose_share + 1e-12 >= min_share
    passed = failed_runtime == 0 and unsafe_fallbacks == 0 and coverage_ok
    report = {
        "schema": "krolik.dwpose-domain-smoke/2",
        "samples": sample_count,
        "runtime_ready": sample_count - failed_runtime,
        "failed_runtime": failed_runtime,
        "dwpose": dwpose_count,
        "dwpose_share": round(dwpose_share, 6),
        "min_dwpose_share": min_share,
        "unsafe_fallbacks": unsafe_fallbacks,
        "review_fallbacks": sum(1 for row in rows if bool(row.get("rig_review_required"))),
        "mean_rig_score": round(mean(scores), 6) if scores else 0.0,
        "median_rig_score": round(median(scores), 6) if scores else 0.0,
        "passed": passed,
        "cases": rows,
    }
    if args.report:
        report_path = Path(args.report).resolve()
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print("KROLIK_DWPOSE_CORPUS " + " ".join(f"{key}={value}" for key, value in report.items() if key != "cases"))
    return 0 if passed else 3


if __name__ == "__main__":
    raise SystemExit(main())
