from __future__ import annotations

"""Versioned AI policy export/validation for the Godot runtime.

`life_sim.py` remains the semantic source of truth. This module validates the
portable policy document and verifies the committed runtime copy cannot drift
silently from Python behavior.
"""

from copy import deepcopy
import json
import math
from pathlib import Path
from typing import Any

from life_sim import AI_POLICY_FORMAT_VERSION, AI_POLICY_SCHEMA, policy_document

ROOT = Path(__file__).resolve().parent
CONTENT_POLICY_PATH = ROOT / "content" / "ai" / "default_policy_v1.json"
RUNTIME_POLICY_PATH = ROOT / "runtime_godot" / "data" / "ai_policy_v1.json"


class AIPolicyError(ValueError):
    pass


def _finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def validate_ai_policy_document(document: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["AI policy must be a JSON object"]
    if document.get("schema") != AI_POLICY_SCHEMA:
        errors.append(f"unsupported AI policy schema: {document.get('schema')!r}")
    if document.get("format_version") != AI_POLICY_FORMAT_VERSION:
        errors.append(f"unsupported AI policy format_version {document.get('format_version')!r}; expected {AI_POLICY_FORMAT_VERSION}")

    defaults = document.get("defaults")
    if not isinstance(defaults, dict):
        errors.append("defaults must be an object"); defaults = {}
    needs = defaults.get("needs") if isinstance(defaults, dict) else None
    profile = defaults.get("profile") if isinstance(defaults, dict) else None
    if not isinstance(needs, dict): errors.append("defaults.needs must be an object"); needs = {}
    if not isinstance(profile, dict): errors.append("defaults.profile must be an object"); profile = {}
    for key in ("energy", "comfort", "curiosity", "social"):
        if not _finite(needs.get(key)) or not 0.0 <= float(needs.get(key, -1.0)) <= 1.0:
            errors.append(f"defaults.needs.{key} must be finite in [0,1]")
    for key in ("autonomy", "wander", "social", "rest_threshold", "curiosity_threshold", "home_bias"):
        if not _finite(profile.get(key)) or not 0.0 <= float(profile.get(key, -1.0)) <= 1.0:
            errors.append(f"defaults.profile.{key} must be finite in [0,1]")
    if not _finite(profile.get("walk_speed")) or not 0.05 <= float(profile.get("walk_speed", 0.0)) <= 4.0:
        errors.append("defaults.profile.walk_speed must be finite in [0.05,4]")

    valid = document.get("valid")
    if not isinstance(valid, dict): errors.append("valid must be an object"); valid = {}
    for key in ("mobility", "routine", "bound_modes"):
        values = valid.get(key)
        if not isinstance(values, list) or not values or not all(isinstance(v, str) and v for v in values):
            errors.append(f"valid.{key} must be a non-empty string array")

    order = document.get("state_order")
    expected_states = {"idle", "wander", "inspect", "social", "return_home", "rest"}
    if not isinstance(order, list) or set(order) != expected_states or len(order) != len(expected_states):
        errors.append("state_order must contain each utility state exactly once")

    gates = document.get("hard_gates")
    if not isinstance(gates, dict): errors.append("hard_gates must be an object"); gates = {}
    for key in ("away_comfort_return", "autonomy_lock", "inspect_no_target_multiplier", "rest_energy_margin", "rest_energy_floor", "rest_ready_multiplier"):
        if not _finite(gates.get(key)):
            errors.append(f"hard_gates.{key} must be finite numeric")
    if _finite(gates.get("rest_ready_multiplier")) and not 0.0 <= float(gates["rest_ready_multiplier"]) <= 1.0:
        errors.append("hard_gates.rest_ready_multiplier must be in [0,1]")

    utility = document.get("utility")
    if not isinstance(utility, dict): errors.append("utility must be an object"); utility = {}
    for section in ("idle", "wander", "inspect", "social", "return_home", "rest", "target", "routine_bonus"):
        values = utility.get(section)
        if not isinstance(values, dict) or not values:
            errors.append(f"utility.{section} must be a non-empty object")
        elif not all(_finite(v) for v in values.values()):
            errors.append(f"utility.{section} values must be finite numeric")

    rates = document.get("need_rates_per_minute")
    if not isinstance(rates, dict): errors.append("need_rates_per_minute must be an object"); rates = {}
    for section in ("rest", "contained", "active", "inspect_override", "social_override", "idle"):
        values = rates.get(section)
        if not isinstance(values, dict) or not values:
            errors.append(f"need_rates_per_minute.{section} must be a non-empty object")
        elif not all(k in {"energy", "comfort", "curiosity", "social"} and _finite(v) for k, v in values.items()):
            errors.append(f"need_rates_per_minute.{section} contains invalid need/rate")

    affect = document.get("affect_thresholds")
    if not isinstance(affect, dict): errors.append("affect_thresholds must be an object"); affect = {}
    for key in ("tired_energy", "uneasy_comfort", "alert_curiosity", "seeking_social"):
        if not _finite(affect.get(key)) or not 0.0 <= float(affect.get(key, -1.0)) <= 1.0:
            errors.append(f"affect_thresholds.{key} must be finite in [0,1]")

    animation = document.get("animation_by_state")
    if not isinstance(animation, dict) or not animation:
        errors.append("animation_by_state must be a non-empty object")
    elif not all(isinstance(k, str) and k and isinstance(v, str) and v for k, v in animation.items()):
        errors.append("animation_by_state must map non-empty strings to non-empty strings")
    return errors


def generated_policy_document() -> dict[str, Any]:
    document = policy_document()
    errors = validate_ai_policy_document(document)
    if errors:
        raise AIPolicyError("life_sim generated an invalid AI policy: " + "; ".join(errors[:12]))
    return deepcopy(document)


def read_policy(path: str | Path) -> dict[str, Any]:
    p = Path(path)
    try:
        document = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise AIPolicyError(f"unable to read AI policy {p}: {exc}") from exc
    errors = validate_ai_policy_document(document)
    if errors:
        raise AIPolicyError(f"invalid AI policy {p}: " + "; ".join(errors[:12]))
    return document


def serialized_generated_policy() -> str:
    return json.dumps(generated_policy_document(), ensure_ascii=False, indent=2, sort_keys=True) + "\n"
