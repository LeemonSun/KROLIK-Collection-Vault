#!/usr/bin/env python3
"""A source scaffold is not a public Steam build. Fail closed on missing evidence."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ("ai_disclosure_completed", "content_guardrails_reviewed",
            "final_asset_rights_reviewed", "third_party_audit_completed",
            "offline_install_tested_on_windows", "cjk_font_bundled",
            "minimum_hardware_benchmarked")

def blockers():
    release = json.loads((ROOT / "config/release.json").read_text())
    result = [key for key in REQUIRED if release.get(key) is not True]
    models = json.loads((ROOT / "manifests/models.json").read_text()).get("models", [])
    if not models:
        result.append("no_approved_bundled_model")
    for model in models:
        if model.get("review_status") != "approved":
            result.append(f"model_not_approved:{model.get('id')}")
        if not model.get("sha256") or not model.get("license"):
            result.append(f"model_provenance_missing:{model.get('id')}")
    characters = json.loads((ROOT / "manifests/characters.json").read_text())
    if not characters.get("final_character"):
        result.append("no_approved_final_character")
    provenance = json.loads((ROOT / "characters/signal_01/provenance.json").read_text())
    if any(asset.get("release_approved") is not True for asset in provenance.get("assets", [])):
        result.append("concept_art_not_cleared_for_release")
    pack = json.loads((ROOT / "manifests/animation_pack.json").read_text())
    if pack.get("review_status") != "approved" or not pack.get("rig_revision") or not pack.get("clips"):
        result.append("rig_and_animation_pack_not_approved")
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--expect-blocked", action="store_true")
    args = parser.parse_args()
    result = blockers()
    print(json.dumps({"release_ready": not result, "blockers": result}, indent=2))
    if args.expect_blocked:
        return 0 if result else 1
    return 1 if result else 0

if __name__ == "__main__":
    sys.exit(main())

