from __future__ import annotations

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
    "mobility": "auto",
    "walk_speed": 1.0,
    "routine": "balanced",
}

MOBILE_STATES = {"idle", "wander", "inspect", "social", "return_home"}
ANIMATION_BY_STATE = {
    "idle": "idle_breathe", "wander": "walk", "inspect": "inspect",
    "social": "social_idle", "return_home": "walk", "contained": "contained_idle",
    "rest": "rest", "disabled": "idle_static",
}


def clamp01(v: float) -> float:
    return max(0.0, min(1.0, float(v)))


def derive_affect(needs: dict[str, float], state: str) -> dict[str, Any]:
    energy, comfort = clamp01(needs.get("energy", .5)), clamp01(needs.get("comfort", .5))
    curiosity, social = clamp01(needs.get("curiosity", .5)), clamp01(needs.get("social", .5))
    if state == "rest" or energy < .22: mood = "tired"
    elif comfort < .28: mood = "uneasy"
    elif curiosity > .78: mood = "alert"
    elif social > .78: mood = "seeking_company"
    else: mood = "calm"
    return {"mood": mood, "energy": energy, "comfort": comfort, "focus": max(curiosity, social),
            "animation": ANIMATION_BY_STATE.get(state, "idle_breathe")}


def merged_profile(value: dict[str, Any] | None) -> dict[str, Any]:
    out = dict(DEFAULT_PROFILE)
    if value: out.update({k: v for k, v in value.items() if k in out})
    for key in ("autonomy", "wander", "social", "rest_threshold", "curiosity_threshold", "home_bias"):
        out[key] = clamp01(out[key])
    out["walk_speed"] = max(.05, min(4.0, float(out["walk_speed"])))
    if out["mobility"] not in {"auto", "free", "contained", "disabled"}: out["mobility"] = "auto"
    if out["routine"] not in {"balanced", "homebody", "explorer", "social"}: out["routine"] = "balanced"
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
    return str(context.get("interaction_mode") or "").lower() in {"bound", "anchored", "contained", "restrained"}


def activity_scores(profile: dict[str, Any], needs: dict[str, float], context: dict[str, Any] | None = None) -> dict[str, float]:
    context = context or {}
    away = bool(context.get("away_from_home", False))
    interesting = max(0.0, float(context.get("interesting_targets", 0.0)))
    social_targets = max(0.0, float(context.get("social_targets", 0.0)))
    routine = profile.get("routine", "balanced")
    explorer_bonus = .18 if routine == "explorer" else 0.0
    social_bonus = .18 if routine == "social" else 0.0
    home_bonus = .20 if routine == "homebody" else 0.0
    return {
        "idle": .20 + needs["comfort"] * .12 + (1.0 - profile["autonomy"]) * .18,
        "wander": .16 + profile["wander"] * .42 + profile["autonomy"] * .20 + needs["curiosity"] * .16 + explorer_bonus,
        "inspect": .12 + needs["curiosity"] * .58 + min(.18, interesting * .06) + explorer_bonus,
        "social": .10 + needs["social"] * .48 + profile["social"] * .28 + min(.18, social_targets * .06) + social_bonus,
        "return_home": (.08 + profile["home_bias"] * .35 + home_bonus + (1.0-needs["comfort"]) * .32 + (1.0-needs["energy"]) * .26) if away else 0.0,
        "rest": .12 + (1.0-needs["energy"]) * .88 + (.18 if not away else -.25),
    }


def choose_state(profile: dict[str, Any], needs: dict[str, float], context: dict[str, Any] | None = None) -> str:
    context = context or {}
    if profile["mobility"] == "disabled": return "disabled"
    if profile["mobility"] == "contained" or (profile["mobility"] == "auto" and is_bound_context(context)): return "contained"
    away = bool(context.get("away_from_home", False))
    if needs["energy"] <= profile["rest_threshold"]: return "return_home" if away else "rest"
    if away and needs["comfort"] < .22: return "return_home"
    scores = activity_scores(profile, needs, context)
    if float(context.get("social_targets", 0.0)) <= 0: scores["social"] = -1.0
    if float(context.get("interesting_targets", 0.0)) <= 0: scores["inspect"] *= .82
    if profile["autonomy"] < .2:
        scores["wander"] = scores["inspect"] = -1.0
    if needs["energy"] > max(profile["rest_threshold"] + .20, .50): scores["rest"] *= .35
    order = ("return_home", "rest", "social", "inspect", "wander", "idle")
    return max(order, key=lambda name: scores.get(name, -1.0))


def step_needs(needs: dict[str, float], state: str, dt: float) -> dict[str, float]:
    minute = max(0.0, min(float(dt), 300.0)) / 60.0
    out = dict(needs)
    if state == "rest":
        out["energy"] = clamp01(out["energy"] + .055*minute); out["comfort"] = clamp01(out["comfort"] + .018*minute); out["curiosity"] = clamp01(out["curiosity"] + .012*minute)
    elif state == "contained":
        out["energy"] = clamp01(out["energy"] - .004*minute); out["comfort"] = clamp01(out["comfort"] - .006*minute); out["curiosity"] = clamp01(out["curiosity"] + .020*minute); out["social"] = clamp01(out["social"] + .010*minute)
    elif state in {"wander", "inspect", "social", "return_home"}:
        out["energy"] = clamp01(out["energy"] - .018*minute); out["comfort"] = clamp01(out["comfort"] - .004*minute); out["curiosity"] = clamp01(out["curiosity"] - (.028 if state == "inspect" else .008)*minute); out["social"] = clamp01(out["social"] - (.025 if state == "social" else .003)*minute)
    else:
        out["energy"] = clamp01(out["energy"] - .005*minute); out["curiosity"] = clamp01(out["curiosity"] + .008*minute); out["social"] = clamp01(out["social"] + .005*minute)
    return out


def step_mind(profile_value: dict[str, Any] | None, needs_value: dict[str, Any] | None, dt: float, context: dict[str, Any] | None = None) -> dict[str, Any]:
    profile, needs = merged_profile(profile_value), merged_needs(needs_value)
    state = choose_state(profile, needs, context)
    needs = step_needs(needs, state, dt)
    next_state = choose_state(profile, needs, context)
    return {"state": next_state, "needs": needs, "profile": profile, "mobile": next_state in MOBILE_STATES,
            "contained": next_state == "contained", "animation": ANIMATION_BY_STATE.get(next_state, "idle_breathe"),
            "affect": derive_affect(needs, next_state), "utility": activity_scores(profile, needs, context)}
