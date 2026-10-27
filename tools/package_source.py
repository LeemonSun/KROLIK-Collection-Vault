#!/usr/bin/env python3
"""Create a deterministic source-only checkpoint, never a pretend executable."""
import argparse
import hashlib
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {".git", ".godot", "build", "dist", "__pycache__", "userdata", "captures", "secrets", "downloads"}
BINARY_MODELS = {".gguf", ".onnx", ".safetensors", ".exe", ".dll", ".pyc", ".log", ".tmp"}

def source_files():
    for path in sorted(ROOT.rglob("*")):
        relative = path.relative_to(ROOT)
        if not path.is_file() or any(p in EXCLUDED for p in relative.parts):
            continue
        if any(p.startswith(".") and p not in {".gitignore", ".gitattributes", ".gdignore"} for p in relative.parts):
            continue
        if path.suffix.lower() in BINARY_MODELS or path.name.startswith(".env") or path.name == "export_credentials.cfg":
            continue
        yield path, relative

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if ROOT == output or ROOT in output.parents:
        raise SystemExit("Put the source archive outside the project tree.")
    output.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path, relative in source_files():
            info = zipfile.ZipInfo("companion-foundation/" + relative.as_posix(),
                                   date_time=(2026, 10, 26, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes())
            count += 1
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(output.suffix + ".sha256").write_text(f"{digest}  {output.name}\n")
    print(f"SOURCE_ARCHIVE: {count} files; {output.stat().st_size} bytes; sha256={digest}")

if __name__ == "__main__":
    main()

