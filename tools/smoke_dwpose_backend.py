from __future__ import annotations

"""Exercise the real rig_tools.detect_rig DWPose path on a supplied image."""

import argparse
import json
from pathlib import Path

from rig_tools import JOINT_ORDER, capabilities, detect_rig, dwpose_diagnostics


def main() -> int:
    parser = argparse.ArgumentParser(description="Require production KROLIK auto-rig to use DWPose ONNX")
    parser.add_argument("image")
    parser.add_argument("--min-confidence", type=float, default=0.18)
    args = parser.parse_args()

    image = Path(args.image).resolve()
    if not image.is_file():
        print(f"KROLIK_DWPOSE_BACKEND status=failed error=image_missing path={image}")
        return 2

    caps = capabilities()
    if not caps.get("dwpose"):
        print(f"KROLIK_DWPOSE_BACKEND status=failed error=dwpose_capability_unavailable caps={caps}")
        return 3

    diagnostics = dwpose_diagnostics(image)
    print("KROLIK_DWPOSE_DIAGNOSTICS " + json.dumps(diagnostics, sort_keys=True, separators=(",", ":")))

    detection = detect_rig(image, prefer_ai=True)
    backend = str(detection.settings.get("backend") or "")
    if backend != "dwpose-onnx":
        print(f"KROLIK_DWPOSE_BACKEND status=failed error=fallback backend={backend}")
        return 4

    missing = [name for name in JOINT_ORDER if name not in detection.joints]
    if missing:
        print(f"KROLIK_DWPOSE_BACKEND status=failed error=missing_joints joints={missing}")
        return 5

    for name in JOINT_ORDER:
        point = detection.joints[name]
        x = float(point.get("x", -1.0))
        y = float(point.get("y", -1.0))
        if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
            print(f"KROLIK_DWPOSE_BACKEND status=failed error=out_of_bounds joint={name} x={x} y={y}")
            return 6

    confidence = float(detection.settings.get("pose_confidence", 0.0))
    if confidence < args.min_confidence:
        print(
            "KROLIK_DWPOSE_BACKEND status=failed "
            f"error=low_confidence confidence={confidence:.6f} min={args.min_confidence:.6f}"
        )
        return 7

    print(
        "KROLIK_DWPOSE_BACKEND status=ok "
        f"backend={backend} joints={len(detection.joints)} confidence={confidence:.6f} "
        f"model={caps.get('dwpose_model')} providers_ready={caps.get('onnxruntime')} opencv={caps.get('opencv')}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
