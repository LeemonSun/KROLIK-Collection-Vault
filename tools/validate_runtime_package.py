from __future__ import annotations

import argparse

from runtime_package_integrity import RuntimePackageIntegrityError, validate_runtime_package_receipt


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate and safely reopen an existing KROLIK runtime package")
    parser.add_argument("package_receipt", help="Path to krolik.runtime-package-receipt/1 JSON")
    args = parser.parse_args()
    try:
        report = validate_runtime_package_receipt(args.package_receipt)
    except RuntimePackageIntegrityError as exc:
        print(f"KROLIK_RUNTIME_PACKAGE_REOPEN status=failed error={exc}")
        return 1
    print(
        "KROLIK_RUNTIME_PACKAGE_REOPEN "
        f"status=ok character_id={report['character_id']} "
        f"manifest_sha256={report['manifest_sha256']} image_sha256={report['image_sha256']} "
        f"source_sha256={report['source_sha256']} cutout_sha256={report['cutout_sha256']} "
        f"rig_edit_verified={report['rig_edit_verified']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
