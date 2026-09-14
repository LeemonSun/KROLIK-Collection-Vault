from __future__ import annotations

"""Verify that the pinned DWPose ONNX matches KROLIK's runtime assumptions.

This is intentionally stronger than checking that an ONNX file can be opened.
`rig_tools.py` expects a single NCHW image input and two SimCC outputs ordered as
X then Y, with a split ratio of 2.0. This smoke performs one CPU inference on a
zero tensor and rejects a model whose shape/output contract would make KROLIK's
current decoder silently wrong.

ONNXRuntime is imported only for the real-model smoke. The ordinary core test
suite can validate the decoder contract with fake sessions without paying the
heavy runtime dependency cost on every push.
"""

import argparse
from pathlib import Path
from typing import Any

import numpy as np

from tools.fetch_dwpose_model import DEFAULT_OUTPUT, MODEL_SHA256, verify_file


class DWPoseContractError(RuntimeError):
    pass


def _static_dim(value: Any, label: str) -> int:
    if isinstance(value, int) and value > 0:
        return value
    raise DWPoseContractError(f"{label} must be a static positive integer, got {value!r}")


def _batch_dim(value: Any) -> tuple[int, bool]:
    """Use batch=1 for the smoke while accepting a symbolic ONNX batch axis."""
    if isinstance(value, int):
        if value <= 0:
            raise DWPoseContractError(f"input batch must be positive, got {value!r}")
        if value != 1:
            raise DWPoseContractError(f"KROLIK smoke expects batch 1, model declares {value}")
        return 1, False
    if isinstance(value, str) and value.strip():
        return 1, True
    if value is None:
        return 1, True
    raise DWPoseContractError(f"unsupported input batch dimension: {value!r}")


def validate_session_contract(session: Any, *, run_inference: bool = True) -> dict[str, Any]:
    inputs = list(session.get_inputs())
    if len(inputs) != 1:
        raise DWPoseContractError(f"expected exactly one model input, got {len(inputs)}")
    inp = inputs[0]
    shape = list(inp.shape)
    if len(shape) != 4:
        raise DWPoseContractError(f"expected NCHW rank-4 input, got {shape}")

    batch, dynamic_batch = _batch_dim(shape[0])
    channels = _static_dim(shape[1], "input channels")
    height = _static_dim(shape[2], "input height")
    width = _static_dim(shape[3], "input width")
    if channels != 3:
        raise DWPoseContractError(f"expected input [batch,3,H,W], got {shape}")

    declared_outputs = list(session.get_outputs())
    if len(declared_outputs) < 2:
        raise DWPoseContractError(f"expected at least two SimCC outputs, got {len(declared_outputs)}")

    output_values: list[np.ndarray]
    if run_inference:
        tensor = np.zeros((batch, channels, height, width), dtype=np.float32)
        output_values = [np.asarray(value) for value in session.run(None, {inp.name: tensor})]
    else:
        output_values = []
        for output in declared_outputs[:2]:
            dims: list[int] = []
            for index, dim in enumerate(output.shape):
                if index == 0 and (isinstance(dim, str) or dim is None):
                    dims.append(1)
                else:
                    dims.append(_static_dim(dim, f"output {output.name} dimension {index}"))
            output_values.append(np.zeros(dims, dtype=np.float32))

    if len(output_values) < 2:
        raise DWPoseContractError("inference returned fewer than two outputs")
    simcc_x, simcc_y = output_values[0], output_values[1]
    if simcc_x.ndim != 3 or simcc_y.ndim != 3:
        raise DWPoseContractError(
            f"expected rank-3 SimCC outputs, got x={simcc_x.shape} y={simcc_y.shape}"
        )
    if simcc_x.shape[0] != 1 or simcc_y.shape[0] != 1:
        raise DWPoseContractError("SimCC output batch must resolve to 1 for the smoke")
    if simcc_x.shape[1] != simcc_y.shape[1] or simcc_x.shape[1] < 17:
        raise DWPoseContractError(
            f"invalid/mismatched keypoint dimension x={simcc_x.shape} y={simcc_y.shape}"
        )

    # rig_tools.py decodes argmax / 2.0. Protect that assumption explicitly.
    expected_x_bins = width * 2
    expected_y_bins = height * 2
    if simcc_x.shape[2] != expected_x_bins or simcc_y.shape[2] != expected_y_bins:
        raise DWPoseContractError(
            "SimCC split-ratio contract mismatch: "
            f"input={width}x{height}, x_bins={simcc_x.shape[2]} expected={expected_x_bins}, "
            f"y_bins={simcc_y.shape[2]} expected={expected_y_bins}"
        )

    return {
        "input_name": str(inp.name),
        "declared_input_shape": shape,
        "input_shape": [batch, channels, height, width],
        "dynamic_batch": dynamic_batch,
        "output_x_shape": [int(v) for v in simcc_x.shape],
        "output_y_shape": [int(v) for v in simcc_y.shape],
        "keypoints": int(simcc_x.shape[1]),
        "simcc_split_ratio": 2.0,
        "providers": list(session.get_providers()),
    }


def inspect_model(path: str | Path) -> dict[str, Any]:
    model = Path(path).resolve()
    valid, reason = verify_file(model)
    if not valid:
        raise DWPoseContractError(f"pinned model integrity failed: {reason}")
    try:
        import onnxruntime as ort  # type: ignore
    except Exception as exc:
        raise DWPoseContractError(f"ONNXRuntime is required for real model smoke: {exc}") from exc
    try:
        session = ort.InferenceSession(str(model), providers=["CPUExecutionProvider"])
    except Exception as exc:
        raise DWPoseContractError(f"ONNXRuntime could not load model: {exc}") from exc
    report = validate_session_contract(session, run_inference=True)
    report["path"] = str(model)
    report["sha256"] = MODEL_SHA256
    report["bytes"] = model.stat().st_size
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the real KROLIK DWPose ONNX input/output contract")
    parser.add_argument("--model", default=str(DEFAULT_OUTPUT))
    args = parser.parse_args()
    try:
        report = inspect_model(args.model)
    except Exception as exc:
        print(f"KROLIK_DWPOSE_CONTRACT status=failed error={exc}")
        return 2

    print(
        "KROLIK_DWPOSE_CONTRACT status=ok "
        f"sha256={report['sha256']} bytes={report['bytes']} "
        f"declared_input={report['declared_input_shape']} runtime_input={report['input_shape']} "
        f"dynamic_batch={report['dynamic_batch']} x={report['output_x_shape']} y={report['output_y_shape']} "
        f"keypoints={report['keypoints']} split={report['simcc_split_ratio']} "
        f"providers={report['providers']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
