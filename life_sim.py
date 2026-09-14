from __future__ import annotations

from copy import deepcopy
from typing import Any


AI_POLICY_SCHEMA = "krolik.ai-policy/1"
AI_POLICY_FORMAT_VERSION = 1

# Semantic source of truth for both editor-side Python simulation and the Godot
# runtime brain. Keep formulas generic and move tunable policy values here so
# runtime export can be generated/verified rather than hand-synchronized.
AI_POLICY: dict[str, Any] = {
    "schema": AI_POLICY_SCHEMA,
    "format_version": AI_POLICY_FORMAT_VERSION,
    "defaults": {
        "needs": {"energy": 0.82, "comfort": 0.72, "curiosity": 0.35, "social": 0.45},
        "profile": {
            "autonomy": 0.75, "wander": 0.65, "social": 0.45,
            "rest_threshold": 0.24, "curiosity_threshold": 0.72,
            "home_bias": 0.35, "mobility": "auto", "walk_speed": 1.0,
            "routine": "balanced",
        },
    },
    "valid": {
        "mobility": ["auto", "free", "contained", "disabled"],
        "routine": ["balanced", "homebody", "explorer", "social"],
        "bound_modes": ["bound", "anchored", "contained", "restrained"],
    },
    "state_order": ["return_home", "rest", "social", "inspect", "wander", "idle"],
    "hard_gates": {
        "away_comfort_return": 0.22,
        "autonomy_lock": 0.20,
        "inspect_no_target_multiplier": 0.82,
        "rest_energy_margin": 0.20,
        "rest_energy_floor": 0.50,
        "rest_ready_multiplier": 0.35,
    },
    "utility": {
        "idle": {"base": 0.20, "comfort": 0.12, "inverse_autonomy": 0.18},
        "wander": {"base": 0.16, "wander": 0.42, "autonomy": 0.20, "curiosity": 0.16},
        "inspect": {"base": 0.12, "curiosity": 0.58},
        "social": {"base": 0.10, "social_need": 0.48, "social_drive": 0.28},
        "return_home": {"base": 0.08, "home_bias": 0.35, "inverse_comfort": 0.32, "inverse_energy": 0.26},
        "rest": {"base": 0.12, "inverse_energy": 0.88, "home_bonus": 0.18, "away_bonus": -0.25},
        "target": {"cap": 0.18, "step": 0.06},
        "routine_bonus": {"explorer": 0.18, "social": 0.18, "homebody": 0.20},
    },
    "need_rates_per_minute": {
        "rest": {"energy": 0.055, "comfort": 0.018, "curiosity": 0.012, "social": 0.0},
        "contained": {"energy": -0.004, "comfort": -0.006, "curiosity": 0.020, "social": 0.010},
        "active": {"energy": -0.018, "comfort": -0.004, "curiosity": -0.008, "social": -0.003},
        "inspect_override": {"curiosity": -0.028},
        "social_override": {"social": -0.025},
        "idle": {"energy": -0.005, "comfort": 0.0, "curiosity": 0.008, "social": 0.005},
    },
    "affect_thresholds": {
        "tired_energy": 0.22, "uneasy_comfort": 0.28,
        "alert_curiosity": 0.78, "seeking_social": 0.78,
    },
    "animation_by_state": {
        "idle": "idle_breathe", "wander": "walk", "inspect": "inspect",
        "social": "social_idle", "return_home": "walk", "contained": "contained_idle",
        "rest": "rest", "disabled": "idle_static",
    },
}


def policy_document() -> dict[str, Any]:
    return deepcopy(AI_POLICY)


DEFAULT_NEEDS = dict(AI_POLICY["defaults"]["needs"])
DEFAULT_PROFILE = dict(AI_POLICY["defaults"]["profile"])
MOBILE_STATES = {"idle", "wander", "inspect", "social", "return_home"}
ANIMATION_BY_STATE = dict(AI_POLICY["animation_by_state"])


def clamp01(v: float) -> float:
    return max(0.0, min(1.0, float(v)))


def derive_affect(needs: dict[str, float], state: str) -> dict[str, Any]:
    energy, comfort = clamp01(needs.get("energy", .5)), clamp01(needs.get("comfort", .5))
    curiosity, social = clamp01(needs.get("curiosity", .5)), clamp01(needs.get("social", .5))
    thresholds = AI_POLICY["affect_thresholds"]
    if state == "rest" or energy < float(thresholds["tired_energy"]): mood = "tired"
    elif comfort < float(thresholds["uneasy_comfort"]): mood = "uneasy"
    elif curiosity > float(thresholds["alert_curiosity"]): mood = "alert"
    elif social > float(thresholds["seeking_social"]): mood = "seeking_company"
    else: mood = "calm"
    return {"mood": mood, "energy": energy, "comfort": comfort, "focus": max(curiosity, social),
            "animation": ANIMATION_BY_STATE.get(state, "idle_breathe")}


def merged_profile(value: dict[str, Any] | None) -> dict[str, Any]:
    out = dict(DEFAULT_PROFILE)
    if value: out.update({k: v for k, v in value.items() if k in out})
    for key in ("autonomy", "wander", "social", "rest_threshold", "curiosity_threshold", "home_bias"):
        out[key] = clamp01(out[key])
    out["walk_speed"] = max(.05, min(4.0, float(out["walk_speed"])))
    valid = AI_POLICY["valid"]
    if out["mobility"] not in set(valid["mobility"]): out["mobility"] = "auto"
    if out["routine"] not in set(valid["routine"]): out["routine"] = "balanced"
    return out


def merged_needs(value: dict[str, Any] | None) -> dict[str, float]:
    out = dict(DEFAULT_NEEDS)
    if value:
        for key in out:
            if key in value: out[key] = clamp01(value[key])
    return out


def is_bound_context(context: dict[str, Any] | None) -> bool:
    if not context: return False
    if context.get("locked") or context.get("bound"): return True
    return str(context.get("interaction_mode") or "").lower() in set(AI_POLICY["valid"]["bound_modes"])


def activity_scores(profile: dict[str, Any], needs: dict[str, float], context: dict[str, Any] | None = None) -> dict[str, float]:
    context = context or {}
    away = bool(context.get("away_from_home", False))
    interesting = max(0.0, float(context.get("interesting_targets", 0.0)))
    social_targets = max(0.0, float(context.get("social_targets", 0.0)))
    utility = AI_POLICY["utility"]; target = utility["target"]; bonuses = utility["routine_bonus"]
    routine = profile.get("routine", "balanced")
    explorer_bonus = float(bonuses["explorer"]) if routine == "explorer" else 0.0
    social_bonus = float(bonuses["social"]) if routine == "social" else 0.0
    home_bonus = float(bonuses["homebody"]) if routine == "homebody" else 0.0
    idle, wander_u, inspect = utility["idle"], utility["wander"], utility["inspect"]
    social_u, return_home, rest = utility["social"], utility["return_home"], utility["rest"]
    return {
        "idle": float(idle["base"]) + needs["comfort"] * float(idle["comfort"]) + (1-profile["autonomy"]) * float(idle["inverse_autonomy"]),
        "wander": float(wander_u["base"]) + profile["wander"]*float(wander_u["wander"]) + profile["autonomy"]*float(wander_u["autonomy"]) + needs["curiosity"]*float(wander_u["curiosity"]) + explorer_bonus,
        "inspect": float(inspect["base"]) + needs["curiosity"]*float(inspect["curiosity"]) + min(float(target["cap"]), interesting*float(target["step"])) + explorer_bonus,
        "social": float(social_u["base"]) + needs["social"]*float(social_u["social_need"]) + profile["social"]*float(social_u["social_drive"]) + min(float(target["cap"]), social_targets*float(target["step"])) + social_bonus,
        "return_home": (float(return_home["base"]) + profile["home_bias"]*float(return_home["home_bias"]) + home_bonus + (1-needs["comfort"])*float(return_home["inverse_comfort"]) + (1-needs["energy"])*float(return_home["inverse_energy"])) if away else 0.0,
        "rest": float(rest["base"]) + (1-needs["energy"])*float(rest["inverse_energy"]) + (float(rest["home_bonus"]) if not away else float(rest["away_bonus"])),
    }


def choose_state(profile: dict[str, Any], needs: dict[str, float], context: dict[str, Any] | None = None) -> str:
    context = context or {}
    if profile["mobility"] == "disabled": return "disabled"
    if profile["mobility"] == "contained" or (profile["mobility"] == "auto" and is_bound_context(context)): return "contained"
    away = bool(context.get("away_from_home", False)); gates = AI_POLICY["hard_gates"]
    if needs["energy"] <= profile["rest_threshold"]: return "return_home" if away else "rest"
    if away and needs["comfort"] < float(gates["away_comfort_return"]): return "return_home"
    scores = activity_scores(profile, needs, context)
    if float(context.get("social_targets", 0.0)) <= 0: scores["social"] = -1.0
    if float(context.get("interesting_targets", 0.0)) <= 0: scores["inspect"] *= float(gates["inspect_no_target_multiplier"])
    if profile["autonomy"] < float(gates["autonomy_lock"]): scores["wander"] = scores["inspect"] = -1.0
    if needs["energy"] > max(profile["rest_threshold"] + float(gates["rest_energy_margin"]), float(gates["rest_energy_floor"])):
        scores["rest"] *= float(gates["rest_ready_multiplier"])
    order = tuple(str(name) for name in AI_POLICY["state_order"])
    return max(order, key=lambda name: scores.get(name, -1.0))


def step_needs(needs: dict[str, float], state: str, dt: float) -> dict[str, float]:
    minute = max(0.0, min(float(dt), 300.0)) / 60.0
    out = dict(needs); rates = AI_POLICY["need_rates_per_minute"]
    if state == "rest": selected = rates["rest"]
    elif state == "contained": selected = rates["contained"]
    elif state in {"wander", "inspect", "social", "return_home"}:
        selected = dict(rates["active"])
        if state == "inspect": selected.update(rates["inspect_override"])
        if state == "social": selected.update(rates["social_override"])
    else: selected = rates["idle"]
    for key in DEFAULT_NEEDS: out[key] = clamp01(out[key] + float(selected.get(key, 0.0))*minute)
    return out


def step_mind(profile_value: dict[str, Any] | None, needs_value: dict[str, Any] | None, dt: float, context: dict[str, Any] | None = None) -> dict[str, Any]:
    profile, needs = merged_profile(profile_value), merged_needs(needs_value)
    state = choose_state(profile, needs, context); needs = step_needs(needs, state, dt); next_state = choose_state(profile, needs, context)
    return {"state": next_state, "needs": needs, "profile": profile, "mobile": next_state in MOBILE_STATES,
            "contained": next_state == "contained", "animation": ANIMATION_BY_STATE.get(next_state, "idle_breathe"),
            "affect": derive_affect(needs, next_state), "utility": activity_scores(profile, needs, context)}
