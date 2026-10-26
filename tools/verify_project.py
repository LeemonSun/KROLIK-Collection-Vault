#!/usr/bin/env python3
"""Validate the source scaffold, without downloading or executing model files."""
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def validate():
    errors = []
    parsed = {}
    for path in sorted(ROOT.rglob("*.json")):
        if ".godot" in path.parts:
            continue
        try:
            parsed[path.relative_to(ROOT).as_posix()] = json.loads(path.read_text(encoding="utf-8"))
        except (ValueError, OSError) as exc:
            errors.append(f"{path.relative_to(ROOT)}: {exc}")
    locales = {code: parsed.get(f"locales/{code}.json", {}) for code in ("ru", "en", "zh-Hans")}
    base = locales["en"]
    if not base:
        errors.append("English catalog missing")
    for code, catalog in locales.items():
        if set(catalog) != set(base):
            errors.append(f"{code}: locale keys differ")
        for key, text in catalog.items():
            if not isinstance(text, str) or not text.strip():
                errors.append(f"{code}/{key}: empty/non-string translation")
                continue
            if set(re.findall(r"\{(\w+)\}", text)) != set(re.findall(r"\{(\w+)\}", base.get(key, ""))):
                errors.append(f"{code}/{key}: interpolation tokens differ")
    product = parsed.get("config/product.json", {})
    if product.get("ui_locales") != ["ru", "en", "zh-Hans"]:
        errors.append("Three initial locales must be declared")
    if product.get("offline_required") is not True or product.get("telemetry") is not False:
        errors.append("Offline/privacy defaults changed")
    profiles = parsed.get("config/profiles.json", {}).get("profiles", {})
    if set(profiles) != {"lite", "balanced", "quality"}:
        errors.append("Profile set invalid")
    for name, profile in profiles.items():
        if profile.get("max_parallel_heavy_jobs") != 1:
            errors.append(f"{name}: heavy job budget must start at one")
        if not 16 <= profile.get("max_tokens", 0) <= 512:
            errors.append(f"{name}: response budget invalid")
    modules = parsed.get("manifests/capabilities.json", {}).get("capabilities", [])
    ids = [m["id"] for m in modules]
    if len(set(ids)) != len(ids):
        errors.append("Duplicate capability ID")
    if "chess_analysis" in ids:
        errors.append("Do not require a chess-specific capability in the generic foundation")
    perception = parsed.get("config/perception.json", {})
    if perception.get("capture_enabled") or perception.get("persist_frames") or perception.get("remote_inference"):
        errors.append("Perception must be disabled/local/non-persistent by default")
    if perception.get("application_specific_engine_required") is not False:
        errors.append("Universal perception requirement missing")
    for path in ROOT.rglob("*.gd"):
        text = path.read_text(encoding="utf-8")
        for resource in re.findall(r'(?:preload|load)\("res://([^"]+)"\)', text):
            if not (ROOT / resource).is_file():
                errors.append(f"{path.name}: missing resource {resource}")
    # Check literal localization keys; dynamic enum-derived keys are covered by parity.
    for path in (ROOT / "src").rglob("*.gd"):
        for key in re.findall(r'\b(?:App\.t|t)\("([a-z_]+)"(?:[,)]|\s*\))', path.read_text()):
            if key not in base:
                errors.append(f"{path.name}: missing localization key {key}")
    forbidden = {".gguf", ".onnx", ".safetensors", ".exe", ".dll"}
    for path in ROOT.rglob("*"):
        if ".godot" in path.parts or not path.is_file():
            continue
        if path.suffix.lower() in forbidden:
            errors.append(f"Unreviewed binary/model in source tree: {path.relative_to(ROOT)}")
        if path.name in {".env", "export_credentials.cfg"}:
            errors.append(f"Credential file must not be shipped: {path.relative_to(ROOT)}")
    if (ROOT / ".github/workflows").exists():
        errors.append("GitHub is storage only: workflows are not allowed")
    registry = parsed.get("manifests/components.json", {})
    for item in registry.get("components", []):
        if item.get("license_file") and not (ROOT / item["license_file"]).is_file():
            errors.append(f"Missing license file for {item['id']}")
    return errors, {"json_files": len(parsed), "locale_keys": len(base),
                    "gd_scripts": len(list(ROOT.rglob("*.gd")))}

def main():
    errors, counts = validate()
    for error in errors:
        print("FAIL:", error)
    print("STRUCTURE:", json.dumps(counts), f"errors={len(errors)}")
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())

