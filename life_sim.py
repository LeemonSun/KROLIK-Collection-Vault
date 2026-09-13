from __future__ import annotations

from dataclasses import dataclass
from typing import Any

DEFAULT_NEEDS = {
    "energy": 0.82,
    "comfort": 0.72,
    "curiosity": 0.35,
    "social": 0.45,
}

DEFAULT_PROFILE = {
    "autonomy": 0.75,
    "wander": 0.65,
    "social": 0.45,
    "rest_threshold": 0.24,
    "curiosity_threshold": 0.72,
    "home_bias": 0.35,
    "mobility": "auto",  # auto | free | contained | disabled
    "walk_speed": 1.0,
}

MOBILE_STATES = {"idle", "wander", "inspect", "social", "return_home"}
IMMOBILE_STATES = {"contained", "rest", "disabled"}


def clamp01(v: float) -> float:
    return max(0.0, min(1.0, float(v)))


def merged_profile(value: dict[str, Any] | None) -> dict[str, Any]:
    out = dict(DEFAULT_PROFILE)
    if value:
        out.update({k: v for k, v in value.items() if k in out})
    out["autonomy"] = clamp01(out["autonomy"])
    out["wander"] = clamp01(out["wander"])
    out["social"] = clamp01(out["social"])
    out["rest_threshold"] = clamp01(out["rest_threshold"])
    out["curiosity_threshold"] = clamp01(out["curiosity_threshold"])
    out["home_bias"] = clamp01(out["home_bias"])
    out["walk_speed"] = max(0.05, min(4.0, float(out["walk_speed"])))
    if out["mobility"] not in {"auto", "free", "contained", "disabled"}:
        out["mobility"] = "auto"
    return out


def merged_needs(value: dict[str, Any] | None) -> dict[str, float]:
    out = dict(DEFAULT_NEEDS)
    if value:
        for k in out:
            if k in value:
                out[k] = clamp01(value[k])
    return out


def is_bound_context(context: dict[str, Any] | None) -> bool:
    if not context:
        return False
    if context.get("locked") or context.get("bound"):
        return True
    mode = str(context.get("interaction_mode") or "").lower()
    return mode in {"bound", "anchored", "contained", "restrained"}


def choose_state(profile: dict[str, Any], needs: dict[str, float], context: dict[str, Any] | None = None) -> str:
    mobility = profile["mobility"]
    if mobility == "disabled":
        return "disabled"
    if mobility == "contained" or (mobility == "auto" and is_bound_context(context)):
        return "contained"
    if needs["energy"] <= profile["rest_threshold"]:
        return "rest"
    if needs["curiosity"] >= profile["curiosity_threshold"] and profile["autonomy"] > 0.2:
        return "inspect"
    if needs["social"] >= 0.76 and profile["social"] >= 0.45:
        return "social"
    if profile["wander"] >= 0.35 and profile["autonomy"] >= 0.35:
        return "wander"
    return "idle"


def step_needs(needs: dict[str, float], state: str, dt: float) -> dict[str, float]:
    dt = max(0.0, min(float(dt), 300.0))
    minute = dt / 60.0
    out = dict(needs)
    if state == "rest":
        out["energy"] = clamp01(out["energy"] + 0.055 * minute)
        out["comfort"] = clamp01(out["comfort"] + 0.018 * minute)
        out["curiosity"] = clamp01(out["curiosity"] + 0.012 * minute)
    elif state == "contained":
        out["energy"] = clamp01(out["energy"] - 0.004 * minute)
        out["comfort"] = clamp01(out["comfort"] - 0.006 * minute)
        out["curiosity"] = clamp01(out["curiosity"] + 0.020 * minute)
        out["social"] = clamp01(out["social"] + 0.010 * minute)
    elif state in {"wander", "inspect", "social", "return_home"}:
        out["energy"] = clamp01(out["energy"] - 0.018 * minute)
        out["comfort"] = clamp01(out["comfort"] - 0.004 * minute)
        out["curiosity"] = clamp01(out["curiosity"] - (0.028 if state == "inspect" else 0.008) * minute)
        out["social"] = clamp01(out["social"] - (0.025 if state == "social" else 0.003) * minute)
    else:
        out["energy"] = clamp01(out["energy"] - 0.005 * minute)
        out["curiosity"] = clamp01(out["curiosity"] + 0.008 * minute)
        out["social"] = clamp01(out["social"] + 0.005 * minute)
    return out


def step_mind(
    profile_value: dict[str, Any] | None,
    needs_value: dict[str, Any] | None,
    dt: float,
    context: dict[str, Any] | None = None,
) -> dict[str, Any]:
    profile = merged_profile(profile_value)
    needs = merged_needs(needs_value)
    state = choose_state(profile, needs, context)
    needs = step_needs(needs, state, dt)
    next_state = choose_state(profile, needs, context)
    return {
        "state": next_state,
        "needs": needs,
        "profile": profile,
        "mobile": next_state in MOBILE_STATES,
        "contained": next_state == "contained",
    }
