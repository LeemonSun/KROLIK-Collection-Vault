#!/usr/bin/env python3
"""Validate the source scaffold, without downloading or executing model files."""
import hashlib
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
    provenance = parsed.get("characters/signal_01/provenance.json", {})
    listed = set()
    for asset in provenance.get("assets", []):
        rel = asset.get("path", "")
        path = ROOT / "characters/signal_01" / rel
        if not rel or ".." in Path(rel).parts or not path.is_file():
            errors.append(f"Character asset missing or invalid: {rel}")
            continue
        listed.add(path.resolve())
        if hashlib.sha256(path.read_bytes()).hexdigest() != asset.get("sha256"):
            errors.append(f"Character asset hash mismatch: {rel}")
        if asset.get("review_status") not in {"reviewed_for_internal_reference_only", "approved"}:
            errors.append(f"Character asset not reviewed: {rel}")
    for path in (ROOT / "characters").rglob("*.png"):
        if path.resolve() not in listed:
            errors.append(f"Character PNG without provenance: {path.relative_to(ROOT)}")
    for asset in provenance.get("runtime_assets", []):
        rel = asset.get("project_path", "")
        path = ROOT / rel
        if not rel or ".." in Path(rel).parts or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != asset.get("sha256"):
            errors.append(f"Runtime character hash mismatch: {rel}")
    leemon = parsed.get("characters/leemon_01/provenance.json", {})
    leemon_path = ROOT / leemon.get("runtime_asset", "missing")
    if not leemon_path.is_file() or hashlib.sha256(leemon_path.read_bytes()).hexdigest() != leemon.get("runtime_asset_sha256"):
        errors.append("Leemon runtime master missing or hash mismatch")
    if leemon.get("release_approved") is not False:
        errors.append("Leemon concept must not imply commercial clearance")
    font = parsed.get("assets/fonts/provenance.json", {})
    font_path = ROOT / "assets/fonts" / font.get("file", "missing")
    if not font_path.is_file() or hashlib.sha256(font_path.read_bytes()).hexdigest() != font.get("sha256"):
        errors.append("Bundled font missing or hash mismatch")
    worker = parsed.get("config/local_worker.json", {})
    if worker.get("download_policy") != "explicit_button_only" or worker.get("publish_to_git") is not False:
        errors.append("Local worker download policy changed")
    if worker.get("runtime", {}).get("version") != "b11901" or not worker.get("runtime", {}).get("files"):
        errors.append("Local runtime pin/allowlist missing")
    for part in [worker.get("runtime", {}), worker.get("model", {})]:
        if not str(part.get("url", "")).startswith(("https://github.com/ggml-org/llama.cpp/releases/download/b11901/", "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/f6d5376be1edb4d416d56da11e5397a961aca8ae/")) or len(str(part.get("sha256", ""))) != 64:
            errors.append("Local package not pinned to reviewed source/hash")
    design = parsed.get("characters/signal_01/design.json", {})
    master = ROOT / "characters/signal_01" / design.get("source_of_truth", "missing")
    if not master.is_file() or hashlib.sha256(master.read_bytes()).hexdigest() != design.get("master_sha256"):
        errors.append("Canonical reference hash does not match design")
    catalog = parsed.get("manifests/animation_catalog.json", {})
    events = catalog.get("events", [])
    event_ids = [event.get("id") for event in events]
    if not events or len(event_ids) != len(set(event_ids)):
        errors.append("Animation event catalog missing or duplicated")
    pack = parsed.get("manifests/animation_pack.json", {})
    if catalog.get("implemented_clips") != len(pack.get("clips", [])):
        errors.append("Animation completed count differs from pack")
    if not (ROOT / "OPEN_PREVIEW.html").is_file():
        errors.append("Local materials preview missing")
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

