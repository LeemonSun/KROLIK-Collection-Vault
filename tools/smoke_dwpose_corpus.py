from __future__ import annotations

"""Run the production KROLIK import/auto-rig path over the pinned art corpus.

The gate requires every sample to produce a runtime-ready package, preserves the
aggregate DWPose coverage floor, requires explicit review for every fallback,
and also rejects per-fixture regressions that aggregate coverage could hide.
"""

import argparse
import json
from pathlib import Path
from statistics import mean, median
import tempfile

from character_import import build_character_runtime_package
from rig_tools import capabilities, dwpose_diagnostics
from tools.validate_dwpose_domain_report import evaluate_report, load_json, validate_expectations

DEFAULT_EXPECTATIONS = Path("qa/corpora/dwpose_domain_art_expectations_v1.json")


def main() -> int:
    parser = argparse.ArgumentParser(description="Gate the production KROLIK auto-rig path on an art corpus")
    parser.add_argument("images", nargs="+")
    parser.add_argument("--min-dwpose-share", type=float, default=0.75)
    parser.add_argument("--report", default="")
    parser.add_argument("--expectations", type=Path, default=DEFAULT_EXPECTATIONS)
    args = parser.parse_args()

    min_share = max(0.0, min(1.0, float(args.min_dwpose_share)))
    expectations = validate_expectations(load_json(args.expectations))
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
                rows.append({"image": image.name, "status": "missing", "runtime_ready": False})
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

            fallback_diag: dict[str, object] = {}
            if backend != "dwpose-onnx":
                diag = dwpose_diagnostics(package["cutout"])
                fallback_diag = {
                    "dwpose_status": str(diag.get("status") or "unknown"),
                    "dwpose_core_above_018": int(diag.get("core_above_018") or 0),
                    "dwpose_core_scores": list(diag.get("core_scores") or []),
                    "dwpose_score_mean": float(diag.get("score_mean") or 0.0),
                }

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
                **fallback_diag,
            }
            rows.append(row)
            print("KROLIK_DWPOSE_CORPUS_CASE " + json.dumps(row, separators=(",", ":"), sort_keys=True))

    sample_count = len(rows)
    dwpose_share = dwpose_count / max(1, sample_count)
    scores = [float(row.get("rig_score", 0.0)) for row in rows if row.get("status") != "missing"]
    coverage_ok = dwpose_share + 1e-12 >= min_share
    per_case_errors = evaluate_report({"cases": rows}, expectations)
    passed = failed_runtime == 0 and unsafe_fallbacks == 0 and coverage_ok and not per_case_errors
    report = {
        "schema": "krolik.dwpose-domain-smoke/3",
        "samples": sample_count,
        "runtime_ready": sample_count - failed_runtime,
        "failed_runtime": failed_runtime,
        "dwpose": dwpose_count,
        "dwpose_share": round(dwpose_share, 6),
        "min_dwpose_share": min_share,
        "unsafe_fallbacks": unsafe_fallbacks,
        "review_fallbacks": sum(1 for row in rows if bool(row.get("rig_review_required"))),
        "per_case_regressions": len(per_case_errors),
        "per_case_errors": per_case_errors,
        "mean_rig_score": round(mean(scores), 6) if scores else 0.0,
        "median_rig_score": round(median(scores), 6) if scores else 0.0,
        "passed": passed,
        "cases": rows,
    }
    if args.report:
        report_path = Path(args.report).resolve()
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    for error in per_case_errors:
        print(f"KROLIK_DWPOSE_EXPECTATION_FAIL {error}")
    print("KROLIK_DWPOSE_CORPUS " + " ".join(f"{key}={value}" for key, value in report.items() if key not in {"cases", "per_case_errors"}))
    return 0 if passed else 3


if __name__ == "__main__":
    raise SystemExit(main())
