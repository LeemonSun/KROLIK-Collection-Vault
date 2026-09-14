from __future__ import annotations

"""Download/verify the exact DWPose ONNX expected by rig_tools.py.

The large model binary is intentionally NOT committed to Git. This bootstrap is
safe to run repeatedly: an existing valid file is reused, downloads land in a
temporary sibling file, SHA-256 is verified before replacement, and a failed or
truncated download never overwrites the last known-good model.
"""

import argparse
from hashlib import sha256
import os
from pathlib import Path
import tempfile
from typing import BinaryIO
from urllib.request import Request, urlopen

MODEL_NAME = "dw-ll_ucoco_384.onnx"
MODEL_SHA256 = "724f4ff2439ed61afb86fb8a1951ec39c6220682803b4a8bd4f598cd913b1843"
MODEL_SIZE_BYTES = 140_839_825
DEFAULT_URL = "https://huggingface.co/fashn-ai/DWPose/resolve/main/dw-ll_ucoco_384.onnx?download=true"
DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / "models" / "dwpose" / MODEL_NAME


def sha256_file(path: str | Path) -> str:
    h = sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def verify_file(
    path: str | Path,
    *,
    expected_sha256: str = MODEL_SHA256,
    expected_size: int | None = MODEL_SIZE_BYTES,
) -> tuple[bool, str]:
    source = Path(path)
    if not source.is_file():
        return False, "missing"
    if expected_size is not None and source.stat().st_size != int(expected_size):
        return False, f"size_mismatch:{source.stat().st_size}"
    digest = sha256_file(source)
    if digest.lower() != expected_sha256.lower():
        return False, f"sha256_mismatch:{digest}"
    return True, digest


def _copy_stream(source: BinaryIO, target: BinaryIO) -> int:
    total = 0
    while True:
        chunk = source.read(1024 * 1024)
        if not chunk:
            break
        target.write(chunk)
        total += len(chunk)
    return total


def download_model(url: str, output: str | Path) -> Path:
    target = Path(output).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)

    valid, _reason = verify_file(target)
    if valid:
        return target

    fd, temp_name = tempfile.mkstemp(prefix=MODEL_NAME + ".", suffix=".download", dir=str(target.parent))
    os.close(fd)
    temp_path = Path(temp_name)
    try:
        request = Request(url, headers={"User-Agent": "KROLIK-Collection-Vault/1.0"})
        with urlopen(request, timeout=120) as response, temp_path.open("wb") as handle:
            written = _copy_stream(response, handle)
            handle.flush()
            os.fsync(handle.fileno())

        valid, reason = verify_file(temp_path)
        if not valid:
            raise RuntimeError(
                f"downloaded DWPose model failed verification ({reason}); bytes={written}; "
                "existing model was left untouched"
            )
        os.replace(temp_path, target)
        return target
    finally:
        try:
            temp_path.unlink()
        except FileNotFoundError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch/verify the pinned KROLIK DWPose ONNX model")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Destination ONNX path")
    parser.add_argument("--url", default=DEFAULT_URL, help="Override download URL; SHA-256 remains pinned")
    parser.add_argument("--check", action="store_true", help="Verify only; do not use the network")
    args = parser.parse_args()

    output = Path(args.output).resolve()
    if args.check:
        valid, reason = verify_file(output)
        print(
            "KROLIK_DWPOSE_MODEL "
            f"status={'ok' if valid else 'missing_or_invalid'} path={output} reason={reason} "
            f"expected_sha256={MODEL_SHA256} expected_bytes={MODEL_SIZE_BYTES}"
        )
        return 0 if valid else 2

    try:
        path = download_model(args.url, output)
    except Exception as exc:
        print(f"KROLIK_DWPOSE_MODEL status=failed path={output} error={exc}")
        return 3

    valid, reason = verify_file(path)
    print(
        "KROLIK_DWPOSE_MODEL "
        f"status={'ok' if valid else 'failed'} path={path} sha256={reason} bytes={path.stat().st_size}"
    )
    return 0 if valid else 4


if __name__ == "__main__":
    raise SystemExit(main())
