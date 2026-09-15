#!/usr/bin/env python3
"""Create many path-unique sealed runtime packages from verified templates.

This is a scale-test helper, not a user import path. It preserves each template's
immutable original/cutout provenance while assigning a new character id, copying
the runtime image into a unique package directory, rewriting the runtime manifest,
and generating a fresh krolik.runtime-package-receipt/1 sidecar.

The resulting packages are independently addressable by the Godot runtime cache,
which lets CI measure the real cost of dozens/hundreds of unique package entries
without repeatedly running cutout/rig generation hundreds of times.
"""

from __future__ import annotations

import argparse
import copy
import json
import shutil
from pathlib import Path
from typing import Any

from import_integrity import validate_import_receipt
from runtime_package_integrity import (
    build_runtime_package_receipt,
    validate_runtime_package_receipt,
    write_runtime_package_receipt,
)

INDEX_SCHEMA = "krolik.qa-runtime-package-index/1"
INDEX_FORMAT_VERSION = 1


class FanoutError(ValueError):
    pass


def _read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise FanoutError(f"unable to read {label} {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise FanoutError(f"{label} must be a JSON object: {path}")
    return value


def _write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def _template_info(package_dir: Path) -> dict[str, Any]:
    manifest_path = package_dir / "manifest.json"
    receipt_path = package_dir / "package_receipt.json"
    if not manifest_path.is_file() or not receipt_path.is_file():
        raise FanoutError(f"template package is incomplete: {package_dir}")

    receipt_report = validate_runtime_package_receipt(receipt_path)
    receipt_doc = _read_json(receipt_path, "runtime package receipt")
    import_record = receipt_doc.get("import")
    if not isinstance(import_record, dict):
        raise FanoutError(f"template receipt has no import record: {receipt_path}")
    source_import_receipt = Path(str(import_record.get("receipt") or ""))
    import_report = validate_import_receipt(source_import_receipt)
    import_doc = _read_json(source_import_receipt, "import receipt")
    manifest_doc = _read_json(manifest_path, "runtime manifest")

    image_path = Path(str(receipt_report["image"]))
    if not image_path.is_file():
        raise FanoutError(f"template image is missing: {image_path}")
    return {
        "package_dir": package_dir,
        "manifest_doc": manifest_doc,
        "image_path": image_path,
        "import_doc": import_doc,
        "import_report": import_report,
    }


def build_fanout(
    template_dirs: list[Path],
    output_root: Path,
    count: int,
    *,
    id_prefix: str = "unique_pkg",
) -> dict[str, Any]:
    if count <= 0:
        raise FanoutError("count must be positive")
    if not template_dirs:
        raise FanoutError("at least one template package is required")
    templates = [_template_info(path.resolve()) for path in template_dirs]

    output_root = output_root.resolve()
    packages_root = output_root / "packages"
    receipts_root = output_root / "import_receipts"
    packages_root.mkdir(parents=True, exist_ok=True)
    receipts_root.mkdir(parents=True, exist_ok=True)

    manifest_paths: list[str] = []
    template_usage: dict[str, int] = {}
    for index in range(count):
        template = templates[index % len(templates)]
        character_id = f"{id_prefix}_{index:04d}"
        package_dir = packages_root / character_id
        package_dir.mkdir(parents=True, exist_ok=True)

        source_image: Path = template["image_path"]
        target_image = package_dir / "character.png"
        shutil.copyfile(source_image, target_image)

        manifest = copy.deepcopy(template["manifest_doc"])
        character = manifest.get("character")
        visual = manifest.get("visual")
        if not isinstance(character, dict) or not isinstance(visual, dict):
            raise FanoutError("template manifest is missing character/visual")
        character["id"] = character_id
        character["name"] = character_id
        visual["file"] = "character.png"
        target_manifest = package_dir / "manifest.json"
        _write_json(target_manifest, manifest)

        import_doc = copy.deepcopy(template["import_doc"])
        import_doc["character_id"] = character_id
        target_import_receipt = receipts_root / f"{character_id}.json"
        _write_json(target_import_receipt, import_doc)
        import_report = validate_import_receipt(target_import_receipt)
        if import_report["character_id"] != character_id:
            raise FanoutError(f"fanout import receipt identity mismatch: {character_id}")

        package_receipt_doc = build_runtime_package_receipt(
            package_folder=package_dir,
            manifest_path=target_manifest,
            image_path=target_image,
            import_receipt_path=target_import_receipt,
        )
        target_package_receipt = package_dir / "package_receipt.json"
        write_runtime_package_receipt(package_receipt_doc, target_package_receipt)
        package_report = validate_runtime_package_receipt(target_package_receipt)
        if package_report["character_id"] != character_id:
            raise FanoutError(f"fanout package identity mismatch: {character_id}")

        manifest_paths.append(target_manifest.as_posix())
        template_key = str(template["package_dir"])
        template_usage[template_key] = template_usage.get(template_key, 0) + 1

    index_doc = {
        "schema": INDEX_SCHEMA,
        "format_version": INDEX_FORMAT_VERSION,
        "count": count,
        "manifests": manifest_paths,
        "template_usage": template_usage,
    }
    index_path = output_root / "package_index.json"
    _write_json(index_path, index_doc)
    return {
        "count": count,
        "index": str(index_path),
        "packages_root": str(packages_root),
        "import_receipts_root": str(receipts_root),
        "manifests": manifest_paths,
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template-package", action="append", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--count", required=True, type=int)
    parser.add_argument("--id-prefix", default="unique_pkg")
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        report = build_fanout(
            args.template_package,
            args.output_root,
            args.count,
            id_prefix=args.id_prefix,
        )
    except (FanoutError, ValueError, OSError) as exc:
        raise SystemExit(f"KROLIK_PACKAGE_FANOUT_FAIL {exc}") from exc
    print(
        "KROLIK_PACKAGE_FANOUT "
        f"status=ok count={report['count']} index={report['index']} "
        f"packages_root={report['packages_root']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
