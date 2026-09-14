from __future__ import annotations

import argparse

from pose_accuracy import PoseAccuracyError, evaluate_corpus


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Measure KROLIK pose backend accuracy against reviewed normalized joint ground truth"
    )
    parser.add_argument("corpus", help="krolik.pose-accuracy-corpus/1 JSON file")
    parser.add_argument(
        "--required-backend",
        default=None,
        help="Fail if detection falls back to a different backend, e.g. dwpose-onnx",
    )
    parser.add_argument("--max-mean-error", type=float, default=None)
    parser.add_argument("--min-pck-05", type=float, default=None)
    parser.add_argument("--min-pck-10", type=float, default=None)
    args = parser.parse_args()

    try:
        summary = evaluate_corpus(args.corpus, required_backend=args.required_backend)
    except PoseAccuracyError as exc:
        print(f"KROLIK_POSE_ACCURACY status=failed error={exc}")
        return 2

    report = summary.as_dict()
    print(
        "KROLIK_POSE_ACCURACY status=ok "
        f"samples={report['samples']} joints={report['joints']} "
        f"mean_error={report['mean_error']:.6f} median_error={report['median_error']:.6f} "
        f"pck_05={report['pck_05']:.6f} pck_10={report['pck_10']:.6f} "
        f"backends={report['backend_counts']}"
    )

    if args.max_mean_error is not None and summary.mean_error > args.max_mean_error:
        print(
            "KROLIK_POSE_ACCURACY_GATE status=failed "
            f"mean_error={summary.mean_error:.6f} max={args.max_mean_error:.6f}"
        )
        return 3
    if args.min_pck_05 is not None and summary.pck_05 < args.min_pck_05:
        print(
            "KROLIK_POSE_ACCURACY_GATE status=failed "
            f"pck_05={summary.pck_05:.6f} min={args.min_pck_05:.6f}"
        )
        return 4
    if args.min_pck_10 is not None and summary.pck_10 < args.min_pck_10:
        print(
            "KROLIK_POSE_ACCURACY_GATE status=failed "
            f"pck_10={summary.pck_10:.6f} min={args.min_pck_10:.6f}"
        )
        return 5
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
