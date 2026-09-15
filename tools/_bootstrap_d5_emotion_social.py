from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    if old not in text:
        raise SystemExit(f"anchor missing in {path}: {old[:100]!r}")
    if text.count(old) != 1:
        raise SystemExit(f"anchor not unique in {path}: {old[:100]!r}")
    write(path, text.replace(old, new, 1))


def regex_once(path: str, pattern: str, replacement: str, flags: int = re.S) -> None:
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"regex expected once in {path}, got {count}: {pattern[:100]!r}")
    write(path, updated)


# Idempotence for workflow reruns after the first commit.
if '"emotion_model": {' in read("life_sim.py") and (ROOT / "runtime_godot/scripts/social_encounter_manager.gd").exists():
    print("D5 emotion/social patch already applied")
    raise SystemExit(0)

emotion_policy = '''    # D5 emotion model is a compact semantic state, not a cosmetic label.
    # It reacts to personality, social encounters and physical constraints while
    # remaining bounded and cheap enough for hundreds of agents.
    "emotion_model": {
        "channels": ["fear", "anger", "sadness", "joy", "trust", "shame", "hope", "frustration", "relief", "curiosity"],
        "response_per_second": 3.2,
        "max_dt": 10.0,
        "constraint_profiles": {
            "none": {"loss_of_control": 0.0, "discomfort": 0.0, "social_exposure": 0.0, "immobility": 0.0},
            "generic": {"loss_of_control": 0.50, "discomfort": 0.30, "social_exposure": 0.20, "immobility": 0.45},
            "contained": {"loss_of_control": 0.58, "discomfort": 0.24, "social_exposure": 0.16, "immobility": 0.62},
            "shackles": {"loss_of_control": 0.68, "discomfort": 0.34, "social_exposure": 0.24, "immobility": 0.60},
            "ankle_shackles": {"loss_of_control": 0.58, "discomfort": 0.30, "social_exposure": 0.20, "immobility": 0.52},
            "cuffs": {"loss_of_control": 0.62, "discomfort": 0.30, "social_exposure": 0.24, "immobility": 0.48},
            "tether": {"loss_of_control": 0.55, "discomfort": 0.22, "social_exposure": 0.24, "immobility": 0.42},
            "rope": {"loss_of_control": 0.66, "discomfort": 0.38, "social_exposure": 0.28, "immobility": 0.66},
            "harness": {"loss_of_control": 0.70, "discomfort": 0.35, "social_exposure": 0.30, "immobility": 0.68},
            "restraint_stool": {"loss_of_control": 0.72, "discomfort": 0.40, "social_exposure": 0.42, "immobility": 0.82},
            "restraint_chair": {"loss_of_control": 0.82, "discomfort": 0.44, "social_exposure": 0.38, "immobility": 0.90},
            "stocks": {"loss_of_control": 0.90, "discomfort": 0.48, "social_exposure": 0.62, "immobility": 0.94},
            "cage": {"loss_of_control": 0.72, "discomfort": 0.28, "social_exposure": 0.34, "immobility": 0.76},
            "wall_anchor": {"loss_of_control": 0.88, "discomfort": 0.46, "social_exposure": 0.45, "immobility": 0.92}
        },
        "facial_moods": ["calm", "tired", "uneasy", "alert", "seeking_company", "terrified", "afraid", "furious", "angry", "sad", "ashamed", "frustrated", "hopeful", "relieved", "happy", "content", "curious", "lonely", "anxious", "determined", "defiant", "resigned"]
    },
'''
replace_once("life_sim.py", '    "need_rates_per_minute": {\n', emotion_policy + '    "need_rates_per_minute": {\n')

emotion_python = r'''
def _emotion_policy() -> dict[str, Any]:
    return AI_POLICY["emotion_model"]


def neutral_emotion_state() -> dict[str, Any]:
    out: dict[str, Any] = {name: 0.0 for name in _emotion_policy()["channels"]}
    out.update({
        "mood": "calm",
        "facial_mood": "calm",
        "intensity": 0.0,
        "valence": 0.0,
        "arousal": 0.0,
        "dominance": 0.5,
    })
    return out


def normalize_emotion_state(value: Any) -> dict[str, Any]:
    out = neutral_emotion_state()
    if not isinstance(value, dict):
        return out
    for name in _emotion_policy()["channels"]:
        out[name] = clamp01(_finite_float(value.get(name), 0.0))
    mood = str(value.get("mood") or out["mood"])
    facial = str(value.get("facial_mood") or mood)
    allowed = set(_emotion_policy()["facial_moods"])
    out["mood"] = mood
    out["facial_mood"] = facial if facial in allowed else "calm"
    out["intensity"] = clamp01(_finite_float(value.get("intensity"), max(float(out[name]) for name in _emotion_policy()["channels"])))
    out["valence"] = max(-1.0, min(1.0, _finite_float(value.get("valence"), 0.0)))
    out["arousal"] = clamp01(_finite_float(value.get("arousal"), 0.0))
    out["dominance"] = clamp01(_finite_float(value.get("dominance"), 0.5))
    return out


def _constraint_kind(context: dict[str, Any]) -> str:
    raw = str(context.get("constraint_kind") or context.get("fixture_kind") or context.get("interaction_mode") or "").lower()
    aliases = (
        (("ankle", "shackle"), "ankle_shackles"),
        (("shackle",), "shackles"),
        (("cuff",), "cuffs"),
        (("stool",), "restraint_stool"),
        (("chair",), "restraint_chair"),
        (("stock",), "stocks"),
        (("cage",), "cage"),
        (("wall", "anchor"), "wall_anchor"),
        (("harness",), "harness"),
        (("rope",), "rope"),
        (("tether",), "tether"),
        (("chain",), "tether"),
    )
    for needles, resolved in aliases:
        if all(needle in raw for needle in needles):
            return resolved
    if raw in _emotion_policy()["constraint_profiles"]:
        return raw
    if raw in {"bound", "anchored", "restrained", "contained"}:
        return "contained"
    return "generic" if raw else "none"


def step_emotion(
    profile_value: dict[str, Any] | None,
    needs_value: dict[str, Any] | None,
    state: str,
    context: dict[str, Any] | None = None,
    previous_value: Any = None,
    dt: float = 0.0,
) -> dict[str, Any]:
    context = context or {}
    profile = merged_profile(profile_value)
    needs = merged_needs(needs_value)
    previous = normalize_emotion_state(previous_value)
    config = _emotion_policy()
    traits = profile["traits"]
    boldness = float(traits["boldness"])
    resilience = float(traits["resilience"])
    patience = float(traits["patience"])
    sociability = float(traits["sociability"])
    curiosity_trait = float(traits["curiosity"])

    bound = bool(context.get("locked") or context.get("bound")) or str(context.get("interaction_mode") or "").lower() in set(AI_POLICY["valid"]["bound_modes"])
    kind = _constraint_kind(context)
    raw_profile = config["constraint_profiles"].get(kind, config["constraint_profiles"]["generic"])
    severity_default = 1.0 if bound else 0.0
    severity = clamp01(_finite_float(context.get("constraint_severity"), severity_default))
    loss = clamp01(float(raw_profile["loss_of_control"]) * severity)
    discomfort = clamp01(float(raw_profile["discomfort"]) * severity + clamp01(_finite_float(context.get("discomfort"), 0.0)) * 0.5)
    exposure = clamp01(float(raw_profile["social_exposure"]) * severity)
    immobility = clamp01(float(raw_profile["immobility"]) * severity)
    threat = clamp01(max(_finite_float(context.get("threat"), 0.0), _finite_float(context.get("danger"), 0.0)))
    pain = clamp01(_finite_float(context.get("pain"), 0.0))
    novelty = clamp01(_finite_float(context.get("constraint_novelty"), 0.55 if bound else 0.0))
    witnesses = clamp01(max(0.0, _finite_float(context.get("witnesses"), 0.0)) / 4.0)
    social_outcome = max(-1.0, min(1.0, _finite_float(context.get("social_success"), 0.0)))
    social_affinity = max(-1.0, min(1.0, _finite_float(context.get("social_affinity"), 0.0)))
    familiarity = clamp01(_finite_float(context.get("social_familiarity"), 0.0))
    positive_social = max(0.0, social_outcome * 0.75 + social_affinity * 0.25)
    negative_social = max(0.0, -social_outcome * 0.70 + -min(0.0, social_affinity) * 0.30)
    released = bool(context.get("released", False))
    safe = bool(context.get("safe", False))

    targets = {name: 0.0 for name in config["channels"]}
    targets["fear"] = clamp01(threat * (0.68 + (1.0 - boldness) * 0.18) + loss * (0.42 - boldness * 0.16) + novelty * 0.14 - resilience * 0.16)
    targets["anger"] = clamp01(loss * (0.18 + boldness * 0.44) + pain * 0.24 + negative_social * 0.35 + threat * boldness * 0.12 - patience * 0.12)
    targets["sadness"] = clamp01(loss * 0.16 + (1.0 - needs["comfort"]) * 0.24 + negative_social * 0.26 - resilience * 0.18)
    targets["frustration"] = clamp01(loss * (0.30 + (1.0 - patience) * 0.28) + discomfort * 0.34 + immobility * 0.16)
    targets["shame"] = clamp01((exposure + witnesses * 0.35) * (0.34 + (1.0 - boldness) * 0.26) + negative_social * 0.12)
    targets["joy"] = clamp01(positive_social * (0.42 + sociability * 0.30) + (0.16 if safe else 0.0))
    targets["trust"] = clamp01(positive_social * (0.34 + sociability * 0.30) + familiarity * max(0.0, social_affinity) * 0.30)
    targets["hope"] = clamp01((0.54 if released else 0.0) + (0.18 if safe else 0.0) + positive_social * 0.20 - threat * 0.12)
    prior_distress = max(float(previous["fear"]), float(previous["frustration"]), float(previous["sadness"]))
    targets["relief"] = clamp01((0.72 if released else 0.0) * max(0.35, prior_distress) + (0.14 if safe else 0.0))
    targets["curiosity"] = clamp01(novelty * (0.18 + curiosity_trait * 0.62) * (1.0 - threat * 0.55) + max(0.0, needs["curiosity"] - 0.65) * 0.28)

    if state == "contained":
        targets["frustration"] = clamp01(targets["frustration"] + 0.10 * (1.0 - patience))
    if needs["energy"] < 0.22:
        targets["sadness"] = clamp01(targets["sadness"] + (0.22 - needs["energy"]) * 0.7)
    if needs["social"] > 0.82 and not positive_social:
        targets["sadness"] = clamp01(targets["sadness"] + (needs["social"] - 0.82) * 0.8)

    safe_dt = max(0.0, min(_finite_float(dt, 0.0), float(config["max_dt"])))
    alpha = 1.0 if safe_dt <= 0.0 else 1.0 - math.exp(-float(config["response_per_second"]) * safe_dt)
    out = neutral_emotion_state()
    for name in config["channels"]:
        out[name] = clamp01(float(previous[name]) + (float(targets[name]) - float(previous[name])) * alpha)

    strongest = max(config["channels"], key=lambda name: float(out[name]))
    intensity = float(out[strongest])
    if out["fear"] >= 0.72:
        mood = "terrified"
    elif strongest == "fear" and intensity >= 0.28:
        mood = "afraid"
    elif out["anger"] >= 0.72:
        mood = "furious"
    elif strongest == "anger" and intensity >= 0.28:
        mood = "angry"
    elif strongest == "shame" and intensity >= 0.28:
        mood = "ashamed"
    elif strongest == "frustration" and intensity >= 0.28:
        mood = "frustrated"
    elif strongest == "sadness" and intensity >= 0.28:
        mood = "sad"
    elif strongest == "relief" and intensity >= 0.24:
        mood = "relieved"
    elif strongest == "joy" and intensity >= 0.25:
        mood = "happy"
    elif strongest == "hope" and intensity >= 0.24:
        mood = "hopeful"
    elif strongest == "curiosity" and intensity >= 0.30:
        mood = "curious"
    elif strongest == "trust" and intensity >= 0.30:
        mood = "content"
    elif state == "rest" or needs["energy"] < 0.22:
        mood = "tired"
    elif needs["comfort"] < 0.28:
        mood = "uneasy"
    elif needs["social"] > 0.82:
        mood = "lonely"
    elif needs["curiosity"] > 0.78:
        mood = "alert"
    else:
        mood = "calm"

    positive = float(out["joy"]) + float(out["trust"]) + float(out["hope"]) + float(out["relief"])
    negative = float(out["fear"]) + float(out["anger"]) + float(out["sadness"]) + float(out["shame"]) + float(out["frustration"])
    out["mood"] = mood
    out["facial_mood"] = mood if mood in set(config["facial_moods"]) else "calm"
    out["intensity"] = clamp01(intensity)
    out["valence"] = max(-1.0, min(1.0, (positive - negative) / 2.5))
    out["arousal"] = clamp01(max(float(out["fear"]), float(out["anger"]), float(out["frustration"]), float(out["joy"]) * 0.7, float(out["curiosity"]) * 0.6))
    out["dominance"] = clamp01(0.25 + profile["autonomy"] * 0.35 + boldness * 0.28 - loss * 0.48 - float(out["fear"]) * 0.18 + float(out["anger"]) * 0.12)
    return out


def derive_affect(
    needs: dict[str, float],
    state: str,
    profile: dict[str, Any] | None = None,
    context: dict[str, Any] | None = None,
    emotion_value: Any = None,
    dt: float = 0.0,
) -> dict[str, Any]:
    out = step_emotion(profile, needs, state, context, emotion_value, dt)
    out["energy"] = clamp01(needs.get("energy", 0.5))
    out["comfort"] = clamp01(needs.get("comfort", 0.5))
    out["focus"] = max(clamp01(needs.get("curiosity", 0.5)), clamp01(needs.get("social", 0.5)))
    out["animation"] = ANIMATION_BY_STATE.get(state, "idle_breathe")
    return out
'''
regex_once(
    "life_sim.py",
    r'def derive_affect\(needs: dict\[str, float\], state: str\) -> dict\[str, Any\]:.*?\n\n\ndef merged_profile',
    emotion_python + '\n\ndef merged_profile',
)

new_step_mind = r'''def step_mind(
    profile_value: dict[str, Any] | None,
    needs_value: dict[str, Any] | None,
    dt: float,
    context: dict[str, Any] | None = None,
    memory_value: Any = None,
    long_term_memory_value: Any = None,
    emotion_value: Any = None,
) -> dict[str, Any]:
    profile = merged_profile(profile_value)
    needs = merged_needs(needs_value)
    memory = normalize_short_term_memory(memory_value)
    long_term_memory = normalize_long_term_memory(long_term_memory_value)
    state = choose_state(profile, needs, context, memory, long_term_memory)
    needs = step_needs(needs, state, dt)
    memory = step_memory(memory, dt)
    long_term_memory = step_long_term_memory(long_term_memory, dt)
    next_state = choose_state(profile, needs, context, memory, long_term_memory)
    affect = derive_affect(needs, next_state, profile, context, emotion_value, dt)
    return {
        "state": next_state,
        "needs": needs,
        "profile": profile,
        "memory": memory,
        "long_term_memory": long_term_memory,
        "mobile": next_state in MOBILE_STATES,
        "contained": next_state == "contained",
        "animation": ANIMATION_BY_STATE.get(next_state, "idle_breathe"),
        "affect": affect,
        "utility": activity_scores(profile, needs, context, memory, long_term_memory),
    }
'''
regex_once("life_sim.py", r'def step_mind\(.*\Z', new_step_mind)

# Python regression coverage.
replace_once(
    "tests/test_life_sim.py",
    "    long_term_utility_bias,\n",
    "    long_term_utility_bias,\n    normalize_emotion_state,\n",
)
replace_once(
    "tests/test_life_sim.py",
    "    step_long_term_memory,\n",
    "    step_long_term_memory,\n    step_emotion,\n",
)
with (ROOT / "tests/test_life_sim.py").open("a", encoding="utf-8") as handle:
    handle.write(r'''


def test_constraint_emotions_depend_on_personality_and_constraint_profile():
    needs = merged_needs({"energy": .8, "comfort": .7, "curiosity": .4, "social": .4})
    context = {
        "bound": True,
        "interaction_mode": "restrained",
        "constraint_kind": "shackles",
        "constraint_severity": .95,
        "constraint_novelty": .8,
        "threat": .72,
        "witnesses": 3,
    }
    timid = merged_profile({"traits": {"boldness": .05, "resilience": .1, "patience": .4}})
    defiant = merged_profile({"traits": {"boldness": .95, "resilience": .95, "patience": .2}})
    timid_affect = step_emotion(timid, needs, "contained", context, None, 1.0)
    defiant_affect = step_emotion(defiant, needs, "contained", context, None, 1.0)
    assert timid_affect["fear"] > defiant_affect["fear"]
    assert defiant_affect["anger"] > timid_affect["anger"]
    assert timid_affect["mood"] in {"terrified", "afraid", "frustrated", "ashamed"}
    assert defiant_affect["mood"] in {"furious", "angry", "frustrated", "afraid"}


def test_constraint_profiles_have_distinct_emotional_load_and_release_creates_relief():
    profile = merged_profile({"traits": {"boldness": .5, "resilience": .5, "patience": .5}})
    needs = merged_needs(None)
    stool = step_emotion(profile, needs, "contained", {
        "bound": True, "constraint_kind": "restraint_stool", "constraint_severity": .7,
    }, None, 1.0)
    stocks = step_emotion(profile, needs, "contained", {
        "bound": True, "constraint_kind": "stocks", "constraint_severity": .9, "witnesses": 4,
    }, None, 1.0)
    assert stocks["frustration"] > stool["frustration"]
    assert stocks["shame"] > stool["shame"]
    released = step_emotion(profile, needs, "idle", {"released": True, "safe": True}, stocks, 0.5)
    assert released["relief"] > .3
    assert released["valence"] > stocks["valence"]


def test_social_outcomes_feed_joy_trust_anger_and_persist_through_step_mind_affect():
    profile = merged_profile({"traits": {"sociability": .9, "boldness": .6}})
    needs = merged_needs({"social": .8})
    positive = step_emotion(profile, needs, "social", {
        "social_success": .9, "social_affinity": .8, "social_familiarity": .8,
    }, None, 1.0)
    negative = step_emotion(profile, needs, "social", {
        "social_success": -.9, "social_affinity": -.7, "social_familiarity": .5,
    }, None, 1.0)
    assert positive["joy"] > negative["joy"]
    assert positive["trust"] > negative["trust"]
    assert negative["anger"] > positive["anger"]
    result = step_mind(profile, needs, 1.0, {"social_targets": 1, "social_success": .9}, [], {}, positive)
    assert set(normalize_emotion_state(result["affect"])) >= {"fear", "anger", "joy", "trust", "mood"}
    assert result["affect"]["facial_mood"]
''')

# Godot semantic emotion mirror.
agent_path = "runtime_godot/scripts/agent_brain.gd"
emotion_fallback = '''const EMOTION_FALLBACK := {
    "channels": ["fear", "anger", "sadness", "joy", "trust", "shame", "hope", "frustration", "relief", "curiosity"],
    "response_per_second": 3.2,
    "max_dt": 10.0,
    "constraint_profiles": {
        "none": {"loss_of_control": 0.0, "discomfort": 0.0, "social_exposure": 0.0, "immobility": 0.0},
        "generic": {"loss_of_control": 0.50, "discomfort": 0.30, "social_exposure": 0.20, "immobility": 0.45},
        "contained": {"loss_of_control": 0.58, "discomfort": 0.24, "social_exposure": 0.16, "immobility": 0.62},
        "shackles": {"loss_of_control": 0.68, "discomfort": 0.34, "social_exposure": 0.24, "immobility": 0.60},
        "ankle_shackles": {"loss_of_control": 0.58, "discomfort": 0.30, "social_exposure": 0.20, "immobility": 0.52},
        "cuffs": {"loss_of_control": 0.62, "discomfort": 0.30, "social_exposure": 0.24, "immobility": 0.48},
        "tether": {"loss_of_control": 0.55, "discomfort": 0.22, "social_exposure": 0.24, "immobility": 0.42},
        "rope": {"loss_of_control": 0.66, "discomfort": 0.38, "social_exposure": 0.28, "immobility": 0.66},
        "harness": {"loss_of_control": 0.70, "discomfort": 0.35, "social_exposure": 0.30, "immobility": 0.68},
        "restraint_stool": {"loss_of_control": 0.72, "discomfort": 0.40, "social_exposure": 0.42, "immobility": 0.82},
        "restraint_chair": {"loss_of_control": 0.82, "discomfort": 0.44, "social_exposure": 0.38, "immobility": 0.90},
        "stocks": {"loss_of_control": 0.90, "discomfort": 0.48, "social_exposure": 0.62, "immobility": 0.94},
        "cage": {"loss_of_control": 0.72, "discomfort": 0.28, "social_exposure": 0.34, "immobility": 0.76},
        "wall_anchor": {"loss_of_control": 0.88, "discomfort": 0.46, "social_exposure": 0.45, "immobility": 0.92},
    },
    "facial_moods": ["calm", "tired", "uneasy", "alert", "seeking_company", "terrified", "afraid", "furious", "angry", "sad", "ashamed", "frustrated", "hopeful", "relieved", "happy", "content", "curious", "lonely", "anxious", "determined", "defiant", "resigned"],
}

'''
replace_once(agent_path, "static var _default_policy_cache: Dictionary = {}\n", emotion_fallback + "static var _default_policy_cache: Dictionary = {}\n")
replace_once(
    agent_path,
    'var long_term_memory: Dictionary = {"relationships": [], "places": [], "favorite_place": ""}\n',
    'var long_term_memory: Dictionary = {"relationships": [], "places": [], "favorite_place": ""}\nvar emotion: Dictionary = {"fear": 0.0, "anger": 0.0, "sadness": 0.0, "joy": 0.0, "trust": 0.0, "shame": 0.0, "hope": 0.0, "frustration": 0.0, "relief": 0.0, "curiosity": 0.0, "mood": "calm", "facial_mood": "calm", "intensity": 0.0, "valence": 0.0, "arousal": 0.0, "dominance": 0.5}\n',
)

emotion_gd = r'''func _emotion_config() -> Dictionary:
    var out := EMOTION_FALLBACK.duplicate(true)
    var configured := _section("emotion_model")
    for key in configured.keys():
        out[key] = configured[key]
    return out

func _neutral_emotion() -> Dictionary:
    return {
        "fear": 0.0, "anger": 0.0, "sadness": 0.0, "joy": 0.0, "trust": 0.0,
        "shame": 0.0, "hope": 0.0, "frustration": 0.0, "relief": 0.0, "curiosity": 0.0,
        "mood": "calm", "facial_mood": "calm", "intensity": 0.0,
        "valence": 0.0, "arousal": 0.0, "dominance": 0.5,
    }

func _normalize_emotion(raw_value: Variant) -> Dictionary:
    var out := _neutral_emotion()
    if typeof(raw_value) != TYPE_DICTIONARY:
        return out
    var raw: Dictionary = raw_value
    var channels = _emotion_config().get("channels", EMOTION_FALLBACK["channels"])
    if typeof(channels) != TYPE_ARRAY:
        channels = EMOTION_FALLBACK["channels"]
    for raw_name in channels:
        var name := str(raw_name)
        out[name] = clampf(float(raw.get(name, 0.0)), 0.0, 1.0)
    var raw_mood := str(raw.get("mood", "calm"))
    var raw_face := str(raw.get("facial_mood", raw_mood))
    var allowed = _emotion_config().get("facial_moods", EMOTION_FALLBACK["facial_moods"])
    out["mood"] = raw_mood
    out["facial_mood"] = raw_face if typeof(allowed) == TYPE_ARRAY and raw_face in allowed else "calm"
    out["intensity"] = clampf(float(raw.get("intensity", 0.0)), 0.0, 1.0)
    out["valence"] = clampf(float(raw.get("valence", 0.0)), -1.0, 1.0)
    out["arousal"] = clampf(float(raw.get("arousal", 0.0)), 0.0, 1.0)
    out["dominance"] = clampf(float(raw.get("dominance", 0.5)), 0.0, 1.0)
    return out

func _constraint_kind(context: Dictionary) -> String:
    var raw := str(context.get("constraint_kind", context.get("fixture_kind", context.get("interaction_mode", "")))).to_lower()
    if "ankle" in raw and "shackle" in raw: return "ankle_shackles"
    if "shackle" in raw: return "shackles"
    if "cuff" in raw: return "cuffs"
    if "stool" in raw: return "restraint_stool"
    if "chair" in raw: return "restraint_chair"
    if "stock" in raw: return "stocks"
    if "cage" in raw: return "cage"
    if "wall" in raw and "anchor" in raw: return "wall_anchor"
    if "harness" in raw: return "harness"
    if "rope" in raw: return "rope"
    if "tether" in raw or "chain" in raw: return "tether"
    var profiles = _emotion_config().get("constraint_profiles", {})
    if typeof(profiles) == TYPE_DICTIONARY and profiles.has(raw): return raw
    if raw in ["bound", "anchored", "restrained", "contained"]: return "contained"
    return "generic" if not raw.is_empty() else "none"

func _trait_value(name: String) -> float:
    return clampf(float(traits.get(name, 0.5)), 0.0, 1.0)

func _step_emotion(context: Dictionary, delta: float) -> void:
    var config := _emotion_config()
    var current := _normalize_emotion(emotion)
    var boldness := _trait_value("boldness")
    var resilience := _trait_value("resilience")
    var patience := _trait_value("patience")
    var sociability := _trait_value("sociability")
    var curiosity_trait := _trait_value("curiosity")
    var bound := _is_bound(context)
    var kind := _constraint_kind(context)
    var profiles = config.get("constraint_profiles", EMOTION_FALLBACK["constraint_profiles"])
    var raw_profile: Dictionary = EMOTION_FALLBACK["constraint_profiles"]["generic"]
    if typeof(profiles) == TYPE_DICTIONARY:
        raw_profile = profiles.get(kind, raw_profile)
    var severity := clampf(float(context.get("constraint_severity", 1.0 if bound else 0.0)), 0.0, 1.0)
    var loss := clampf(float(raw_profile.get("loss_of_control", 0.5)) * severity, 0.0, 1.0)
    var discomfort := clampf(float(raw_profile.get("discomfort", 0.3)) * severity + clampf(float(context.get("discomfort", 0.0)), 0.0, 1.0) * 0.5, 0.0, 1.0)
    var exposure := clampf(float(raw_profile.get("social_exposure", 0.2)) * severity, 0.0, 1.0)
    var immobility := clampf(float(raw_profile.get("immobility", 0.45)) * severity, 0.0, 1.0)
    var threat := clampf(maxf(float(context.get("threat", 0.0)), float(context.get("danger", 0.0))), 0.0, 1.0)
    var pain := clampf(float(context.get("pain", 0.0)), 0.0, 1.0)
    var novelty := clampf(float(context.get("constraint_novelty", 0.55 if bound else 0.0)), 0.0, 1.0)
    var witnesses := clampf(maxf(0.0, float(context.get("witnesses", 0.0))) / 4.0, 0.0, 1.0)
    var social_outcome := clampf(float(context.get("social_success", 0.0)), -1.0, 1.0)
    var social_affinity := clampf(float(context.get("social_affinity", 0.0)), -1.0, 1.0)
    var familiarity := clampf(float(context.get("social_familiarity", 0.0)), 0.0, 1.0)
    var positive_social := maxf(0.0, social_outcome * 0.75 + social_affinity * 0.25)
    var negative_social := maxf(0.0, -social_outcome * 0.70 + -minf(0.0, social_affinity) * 0.30)
    var released := bool(context.get("released", false))
    var safe := bool(context.get("safe", false))
    var targets := {
        "fear": clampf(threat * (0.68 + (1.0 - boldness) * 0.18) + loss * (0.42 - boldness * 0.16) + novelty * 0.14 - resilience * 0.16, 0.0, 1.0),
        "anger": clampf(loss * (0.18 + boldness * 0.44) + pain * 0.24 + negative_social * 0.35 + threat * boldness * 0.12 - patience * 0.12, 0.0, 1.0),
        "sadness": clampf(loss * 0.16 + (1.0 - comfort) * 0.24 + negative_social * 0.26 - resilience * 0.18, 0.0, 1.0),
        "frustration": clampf(loss * (0.30 + (1.0 - patience) * 0.28) + discomfort * 0.34 + immobility * 0.16, 0.0, 1.0),
        "shame": clampf((exposure + witnesses * 0.35) * (0.34 + (1.0 - boldness) * 0.26) + negative_social * 0.12, 0.0, 1.0),
        "joy": clampf(positive_social * (0.42 + sociability * 0.30) + (0.16 if safe else 0.0), 0.0, 1.0),
        "trust": clampf(positive_social * (0.34 + sociability * 0.30) + familiarity * maxf(0.0, social_affinity) * 0.30, 0.0, 1.0),
        "hope": clampf((0.54 if released else 0.0) + (0.18 if safe else 0.0) + positive_social * 0.20 - threat * 0.12, 0.0, 1.0),
        "relief": 0.0,
        "curiosity": clampf(novelty * (0.18 + curiosity_trait * 0.62) * (1.0 - threat * 0.55) + maxf(0.0, curiosity - 0.65) * 0.28, 0.0, 1.0),
    }
    var prior_distress := maxf(float(current.get("fear", 0.0)), maxf(float(current.get("frustration", 0.0)), float(current.get("sadness", 0.0))))
    targets["relief"] = clampf((0.72 if released else 0.0) * maxf(0.35, prior_distress) + (0.14 if safe else 0.0), 0.0, 1.0)
    if state == "contained": targets["frustration"] = clampf(float(targets["frustration"]) + 0.10 * (1.0 - patience), 0.0, 1.0)
    if energy < 0.22: targets["sadness"] = clampf(float(targets["sadness"]) + (0.22 - energy) * 0.7, 0.0, 1.0)
    if social > 0.82 and positive_social <= 0.0: targets["sadness"] = clampf(float(targets["sadness"]) + (social - 0.82) * 0.8, 0.0, 1.0)
    var safe_delta := clampf(delta, 0.0, float(config.get("max_dt", 10.0)))
    var alpha := 1.0 if safe_delta <= 0.0 else 1.0 - exp(-float(config.get("response_per_second", 3.2)) * safe_delta)
    var channels = config.get("channels", EMOTION_FALLBACK["channels"])
    if typeof(channels) != TYPE_ARRAY: channels = EMOTION_FALLBACK["channels"]
    var next := _neutral_emotion()
    var strongest := "fear"
    var intensity := -1.0
    for raw_name in channels:
        var name := str(raw_name)
        var value := clampf(float(current.get(name, 0.0)) + (float(targets.get(name, 0.0)) - float(current.get(name, 0.0))) * alpha, 0.0, 1.0)
        next[name] = value
        if value > intensity:
            strongest = name
            intensity = value
    var next_mood := "calm"
    if float(next["fear"]) >= 0.72: next_mood = "terrified"
    elif strongest == "fear" and intensity >= 0.28: next_mood = "afraid"
    elif float(next["anger"]) >= 0.72: next_mood = "furious"
    elif strongest == "anger" and intensity >= 0.28: next_mood = "angry"
    elif strongest == "shame" and intensity >= 0.28: next_mood = "ashamed"
    elif strongest == "frustration" and intensity >= 0.28: next_mood = "frustrated"
    elif strongest == "sadness" and intensity >= 0.28: next_mood = "sad"
    elif strongest == "relief" and intensity >= 0.24: next_mood = "relieved"
    elif strongest == "joy" and intensity >= 0.25: next_mood = "happy"
    elif strongest == "hope" and intensity >= 0.24: next_mood = "hopeful"
    elif strongest == "curiosity" and intensity >= 0.30: next_mood = "curious"
    elif strongest == "trust" and intensity >= 0.30: next_mood = "content"
    elif state == "rest" or energy < 0.22: next_mood = "tired"
    elif comfort < 0.28: next_mood = "uneasy"
    elif social > 0.82: next_mood = "lonely"
    elif curiosity > 0.78: next_mood = "alert"
    var positive := float(next["joy"]) + float(next["trust"]) + float(next["hope"]) + float(next["relief"])
    var negative := float(next["fear"]) + float(next["anger"]) + float(next["sadness"]) + float(next["shame"]) + float(next["frustration"])
    next["mood"] = next_mood
    next["facial_mood"] = next_mood
    next["intensity"] = clampf(intensity, 0.0, 1.0)
    next["valence"] = clampf((positive - negative) / 2.5, -1.0, 1.0)
    next["arousal"] = clampf(maxf(float(next["fear"]), maxf(float(next["anger"]), maxf(float(next["frustration"]), maxf(float(next["joy"]) * 0.7, float(next["curiosity"]) * 0.6)))), 0.0, 1.0)
    next["dominance"] = clampf(0.25 + autonomy * 0.35 + boldness * 0.28 - loss * 0.48 - float(next["fear"]) * 0.18 + float(next["anger"]) * 0.12, 0.0, 1.0)
    emotion = next

func affect_snapshot() -> Dictionary:
    var out := _normalize_emotion(emotion)
    out["energy"] = energy
    out["comfort"] = comfort
    out["focus"] = maxf(curiosity, social)
    return out

'''
replace_once(agent_path, "func _apply_policy_defaults() -> void:\n", emotion_gd + "func _apply_policy_defaults() -> void:\n")
replace_once(
    agent_path,
    '    long_term_memory = _normalize_long_term_memory(data.get("long_term_memory", {}))\n    _memory_elapsed = 0.0\n',
    '    long_term_memory = _normalize_long_term_memory(data.get("long_term_memory", {}))\n    emotion = _normalize_emotion(data.get("affect", {}))\n    _memory_elapsed = 0.0\n',
)
replace_once(
    agent_path,
    "    state = choose_state(context)\n    _update_mood()\n    return state\n",
    "    state = choose_state(context)\n    _step_emotion(context, clamped_delta)\n    mood = str(emotion.get(\"mood\", mood))\n    return state\n",
)
replace_once(agent_path, '        "affect": {"mood": mood},\n', '        "affect": affect_snapshot(),\n')

# Facial presets for the richer semantic emotion vocabulary.
face_path = "runtime_godot/scripts/facial_state.gd"
face_cases = '''        "uneasy":
            return {"eye_open": 0.88, "brow": 0.20, "mouth_curve": -0.18, "mouth_open": 0.03, "head_x": 0.002, "head_y": 0.006}
        "seeking_company":
            return {"eye_open": 0.94, "brow": 0.12, "mouth_curve": 0.10, "mouth_open": 0.02, "head_x": 0.0, "head_y": -0.002}
        "terrified":
            return {"eye_open": 1.0, "brow": 0.72, "mouth_curve": -0.40, "mouth_open": 0.34, "head_x": 0.0, "head_y": -0.014}
        "furious":
            return {"eye_open": 0.70, "brow": -0.72, "mouth_curve": -0.48, "mouth_open": 0.12, "head_x": 0.0, "head_y": -0.008}
        "ashamed":
            return {"eye_open": 0.68, "brow": -0.08, "mouth_curve": -0.22, "mouth_open": 0.01, "head_x": -0.008, "head_y": 0.016}
        "frustrated":
            return {"eye_open": 0.80, "brow": -0.40, "mouth_curve": -0.24, "mouth_open": 0.05, "head_x": 0.005, "head_y": -0.002}
        "hopeful":
            return {"eye_open": 0.96, "brow": 0.20, "mouth_curve": 0.22, "mouth_open": 0.02, "head_x": 0.0, "head_y": -0.006}
        "relieved":
            return {"eye_open": 0.72, "brow": 0.05, "mouth_curve": 0.24, "mouth_open": 0.03, "head_x": 0.0, "head_y": 0.008}
        "content":
            return {"eye_open": 0.82, "brow": 0.04, "mouth_curve": 0.30, "mouth_open": 0.0, "head_x": 0.0, "head_y": 0.004}
        "curious":
            return {"eye_open": 0.98, "brow": 0.28, "mouth_curve": 0.04, "mouth_open": 0.02, "head_x": 0.008, "head_y": -0.006}
        "lonely":
            return {"eye_open": 0.76, "brow": -0.16, "mouth_curve": -0.32, "mouth_open": 0.01, "head_x": -0.004, "head_y": 0.012}
        "anxious":
            return {"eye_open": 0.98, "brow": 0.38, "mouth_curve": -0.20, "mouth_open": 0.08, "head_x": 0.004, "head_y": -0.006}
        "determined":
            return {"eye_open": 0.84, "brow": -0.28, "mouth_curve": -0.04, "mouth_open": 0.0, "head_x": 0.0, "head_y": -0.006}
        "defiant":
            return {"eye_open": 0.88, "brow": -0.34, "mouth_curve": 0.10, "mouth_open": 0.0, "head_x": 0.006, "head_y": -0.008}
        "resigned":
            return {"eye_open": 0.64, "brow": -0.10, "mouth_curve": -0.18, "mouth_open": 0.01, "head_x": -0.004, "head_y": 0.018}
'''
replace_once(face_path, '        "tired":\n', face_cases + '        "tired":\n')

# Runtime constraint metadata remains backwards-compatible and data-driven.
write("runtime_godot/scripts/constraint_binding.gd", '''class_name VaultConstraintBinding
extends RefCounted

var joint := ""
var prop_id := 0
var anchor := "center"
var enabled := true
var strength := 1.0
var constraint_kind := "generic"
var discomfort := 0.0
var threat := 0.0
var social_exposure := 0.0
var mobility_limit := 0.0

func from_dict(data: Dictionary) -> VaultConstraintBinding:
    joint = str(data.get("joint", joint))
    prop_id = int(data.get("prop_id", prop_id))
    anchor = str(data.get("anchor", anchor))
    enabled = bool(data.get("enabled", enabled))
    strength = clampf(float(data.get("strength", strength)), 0.0, 1.0)
    constraint_kind = str(data.get("constraint_kind", data.get("kind", constraint_kind)))
    discomfort = clampf(float(data.get("discomfort", discomfort)), 0.0, 1.0)
    threat = clampf(float(data.get("threat", threat)), 0.0, 1.0)
    social_exposure = clampf(float(data.get("social_exposure", social_exposure)), 0.0, 1.0)
    mobility_limit = clampf(float(data.get("mobility_limit", mobility_limit)), 0.0, 1.0)
    return self
''')

# Character agent: feed constraints/social context into the brain and face.
char_path = "runtime_godot/scripts/character_agent.gd"
replace_once(
    char_path,
    "var _navigation_target := Vector2.ZERO\n",
    '''var _navigation_target := Vector2.ZERO
var interaction_context: Dictionary = {}
var social_target_id := ""
var social_target_position := Vector2.ZERO
var social_target_valid := false
var social_candidate_count := 0
var social_affinity := 0.0
var social_familiarity := 0.0
var social_event_outcome := 0.0
var social_event_timer := 0.0
var nearby_witnesses := 0
var _last_face_mood := ""
''',
)

interaction_methods = r'''func _normalized_constraint_kind(value: String) -> String:
    var raw := value.to_lower()
    if "ankle" in raw and "shackle" in raw: return "ankle_shackles"
    if "shackle" in raw: return "shackles"
    if "cuff" in raw: return "cuffs"
    if "stool" in raw: return "restraint_stool"
    if "chair" in raw: return "restraint_chair"
    if "stock" in raw: return "stocks"
    if "cage" in raw: return "cage"
    if "wall" in raw and "anchor" in raw: return "wall_anchor"
    if "harness" in raw: return "harness"
    if "rope" in raw: return "rope"
    if "tether" in raw or "chain" in raw: return "tether"
    if raw in ["bound", "anchored", "restrained", "contained"]: return "contained"
    return raw if not raw.is_empty() else "generic"

func _interaction_semantics(data: Dictionary) -> Dictionary:
    var count := runtime_constraints.size()
    var constrained := count > 0 or bool(data.get("contained", false))
    var raw_kind := str(data.get("constraint_kind", data.get("fixture_kind", data.get("kind", data.get("interaction_mode", "")))))
    var severity_default := clampf(0.18 + float(count) * 0.18 + (0.18 if bool(data.get("contained", false)) else 0.0), 0.0, 1.0) if constrained else 0.0
    return {
        "constraint_kind": _normalized_constraint_kind(raw_kind),
        "constraint_severity": clampf(float(data.get("constraint_severity", severity_default)), 0.0, 1.0),
        "constraint_novelty": clampf(float(data.get("constraint_novelty", 0.55 if constrained else 0.0)), 0.0, 1.0),
        "discomfort": clampf(float(data.get("discomfort", 0.0)), 0.0, 1.0),
        "threat": clampf(float(data.get("threat", 0.0)), 0.0, 1.0),
        "pain": clampf(float(data.get("pain", 0.0)), 0.0, 1.0),
        "witnesses": maxi(0, int(data.get("witnesses", 0))),
        "safe": bool(data.get("safe", false)),
        "released": bool(data.get("released", false)),
    }

func set_social_runtime_context(target_id: String, target_pos: Vector2, candidate_count: int, affinity: float, familiarity: float) -> void:
    social_target_id = target_id
    social_target_position = target_pos
    social_target_valid = not target_id.is_empty()
    social_candidate_count = maxi(0, candidate_count)
    social_affinity = clampf(affinity, -1.0, 1.0)
    social_familiarity = clampf(familiarity, 0.0, 1.0)

func set_nearby_witnesses(value: int) -> void:
    nearby_witnesses = maxi(0, value)

func relationship_to(subject: String) -> Dictionary:
    for raw in brain.long_term_snapshot().get("relationships", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = raw
        if str(entry.get("subject", "")) == subject:
            return entry.duplicate(true)
    return {}

func register_social_encounter(partner_id: String, outcome: float) -> void:
    var resolved := clampf(outcome, -1.0, 1.0)
    brain.remember_event("social", partner_id, resolved, 0.78, 240.0)
    brain.reinforce_relationship(partner_id, resolved, 0.72)
    social_event_outcome = resolved
    social_event_timer = 6.0
    var relation := relationship_to(partner_id)
    social_affinity = float(relation.get("affinity", social_affinity))
    social_familiarity = float(relation.get("familiarity", social_familiarity))

'''
regex_once(
    char_path,
    r'func apply_runtime_interaction\(data: Dictionary\) -> void:.*?\nfunc _solve_runtime_constraints',
    interaction_methods + r'''func apply_runtime_interaction(data: Dictionary) -> void:
    var was_contained := contained
    runtime_constraints.clear()
    for raw in data.get("constraints", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var item: Dictionary = raw.duplicate(true)
        var t: Dictionary = item.get("target", {})
        item["target_v"] = Vector2(float(t.get("x", 0.5)), float(t.get("y", 0.5)))
        runtime_constraints.append(item)
    contained = bool(data.get("contained", contained)) or not runtime_constraints.is_empty()
    interaction_context = _interaction_semantics(data)
    interaction_context["released"] = bool(data.get("released", false)) or (was_contained and not contained)
    _solve_runtime_constraints(animated_joints if not animated_joints.is_empty() else rig_joints)
    _apply_visual_transform()
    queue_redraw()

func _solve_runtime_constraints''',
)

new_physics = r'''func _physics_process(delta: float) -> void:
    phase += delta
    social_event_timer = maxf(0.0, social_event_timer - delta)
    var mind_context := {
        "bound": contained,
        "interaction_mode": "contained" if contained else "",
        "away_from_home": global_position.distance_to(home_position) > 36.0,
        "interesting_targets": float(world_targets.size()),
        "social_targets": float(social_candidate_count),
        "social_subject": social_target_id,
        "social_affinity": social_affinity,
        "social_familiarity": social_familiarity,
        "social_success": social_event_outcome if social_event_timer > 0.0 else 0.0,
    }
    for key in interaction_context.keys():
        mind_context[key] = interaction_context[key]
    mind_context["witnesses"] = maxf(float(mind_context.get("witnesses", 0.0)), float(nearby_witnesses))
    brain.state = brain.step(delta, mind_context)
    walk_speed = 80.0 * brain.walk_speed
    match brain.state:
        "wander", "inspect", "social", "return_home":
            if brain.state == "social" and social_target_valid:
                target_position = social_target_position
                _navigation_target_valid = false
            elif global_position.distance_to(target_position) < 8.0:
                _choose_target()
            var waypoint := _movement_waypoint()
            var desired := global_position.direction_to(waypoint) * walk_speed
            if brain.state == "social" and social_target_valid and global_position.distance_to(social_target_position) < 34.0:
                desired = Vector2.ZERO
            velocity = velocity.move_toward(desired, acceleration * delta)
            move_and_slide()
            if absf(velocity.x) > 0.5:
                facing = signf(velocity.x)
        "rest", "contained", "idle", "disabled":
            velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
            if velocity.length_squared() > .01:
                move_and_slide()
    var affect := brain.affect_snapshot()
    var face_mood := str(affect.get("facial_mood", affect.get("mood", "calm")))
    if face_mood != _last_face_mood:
        if facial_state.set_mood(face_mood, maxf(0.18, float(affect.get("intensity", 0.0))), 0.28):
            _last_face_mood = face_mood
    animation_driver.set_state(brain.state)
    var sample := animation_driver.step(delta)
    _visual_offset = sample.get("offset", Vector2.ZERO)
    _visual_rotation = float(sample.get("rotation", 0.0))
    _visual_scale = sample.get("scale", Vector2.ONE)
    _apply_animation_pose(sample, delta)
    _apply_visual_transform()
    queue_redraw()

func _animation_for_state'''
regex_once(char_path, r'func _physics_process\(delta: float\) -> void:.*?\nfunc _animation_for_state', new_physics)
replace_once(
    char_path,
    '    if not world_targets.is_empty():\n',
    '    if brain.state == "social" and social_target_valid:\n        target_position = social_target_position\n        _navigation_target_valid = false\n        _sync_navigation_target()\n        return\n    if not world_targets.is_empty():\n',
)

# Spatially bounded D5 encounter manager.
write("runtime_godot/scripts/social_encounter_manager.gd", r'''class_name VaultSocialEncounterManager
extends RefCounted

var cell_size := 128.0
var scan_interval := 0.30
var approach_radius := 120.0
var encounter_distance := 42.0
var encounter_duration := 1.8
var cooldown_seconds := 8.0
var max_neighbor_checks := 18

var _scan_elapsed := 0.0
var _active_pairs: Dictionary = {}
var _cooldowns: Dictionary = {}
var completed_total := 0
var last_neighbor_checks := 0

func _pair_key(a: VaultCharacterAgent, b: VaultCharacterAgent) -> String:
    var left := a.character_id
    var right := b.character_id
    return "%s|%s" % [left, right] if left < right else "%s|%s" % [right, left]

func _eligible(agent: VaultCharacterAgent) -> bool:
    return agent != null and is_instance_valid(agent) and agent.brain.enabled and agent.brain.mobility != "disabled"

func _social_eligible(agent: VaultCharacterAgent) -> bool:
    return _eligible(agent) and not agent.contained

func _cell(position: Vector2) -> Vector2i:
    return Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))

func _relationship(agent: VaultCharacterAgent, other_id: String) -> Dictionary:
    return agent.relationship_to(other_id)

func _decrement_cooldowns(delta: float) -> void:
    var expired: Array = []
    for key in _cooldowns.keys():
        var remaining := maxf(0.0, float(_cooldowns[key]) - delta)
        if remaining <= 0.0:
            expired.append(key)
        else:
            _cooldowns[key] = remaining
    for key in expired:
        _cooldowns.erase(key)

func _active_ids() -> Dictionary:
    var out: Dictionary = {}
    for pair in _active_pairs.values():
        var a = pair.get("a", null)
        var b = pair.get("b", null)
        if a is VaultCharacterAgent and is_instance_valid(a): out[a.character_id] = true
        if b is VaultCharacterAgent and is_instance_valid(b): out[b.character_id] = true
    return out

func _encounter_outcome(a: VaultCharacterAgent, b: VaultCharacterAgent, pair_key: String) -> float:
    var rel_a := _relationship(a, b.character_id)
    var rel_b := _relationship(b, a.character_id)
    var affinity := (float(rel_a.get("affinity", 0.0)) + float(rel_b.get("affinity", 0.0))) * 0.5
    var familiarity := (float(rel_a.get("familiarity", 0.0)) + float(rel_b.get("familiarity", 0.0))) * 0.5
    var social_drive := (a.brain.social_drive + b.brain.social_drive) * 0.5
    var patience := (float(a.brain.traits.get("patience", 0.5)) + float(b.brain.traits.get("patience", 0.5))) * 0.5
    var raw_hash := absi(hash("%s:%d" % [pair_key, completed_total])) % 1001
    var jitter := (float(raw_hash) / 1000.0 - 0.5) * 0.24
    return clampf(0.10 + (social_drive - 0.5) * 0.38 + (patience - 0.5) * 0.18 + affinity * 0.52 + familiarity * 0.14 + jitter, -1.0, 1.0)

func _resolve_pair(key: String, pair: Dictionary) -> void:
    var a = pair.get("a", null)
    var b = pair.get("b", null)
    if not (a is VaultCharacterAgent) or not (b is VaultCharacterAgent):
        _cooldowns[key] = cooldown_seconds * 0.5
        return
    if not is_instance_valid(a) or not is_instance_valid(b):
        _cooldowns[key] = cooldown_seconds * 0.5
        return
    var outcome := _encounter_outcome(a, b, key)
    a.register_social_encounter(b.character_id, outcome)
    b.register_social_encounter(a.character_id, outcome)
    completed_total += 1
    _cooldowns[key] = cooldown_seconds + float(absi(hash(key)) % 300) / 100.0

func _step_active(delta: float) -> void:
    var finished: Array = []
    for key in _active_pairs.keys():
        var pair: Dictionary = _active_pairs[key]
        var a = pair.get("a", null)
        var b = pair.get("b", null)
        if not (a is VaultCharacterAgent) or not (b is VaultCharacterAgent) or not is_instance_valid(a) or not is_instance_valid(b) or a.contained or b.contained:
            finished.append(key)
            continue
        a.set_social_runtime_context(b.character_id, b.global_position, 1, float(_relationship(a, b.character_id).get("affinity", 0.0)), float(_relationship(a, b.character_id).get("familiarity", 0.0)))
        b.set_social_runtime_context(a.character_id, a.global_position, 1, float(_relationship(b, a.character_id).get("affinity", 0.0)), float(_relationship(b, a.character_id).get("familiarity", 0.0)))
        pair["elapsed"] = float(pair.get("elapsed", 0.0)) + delta
        _active_pairs[key] = pair
        if float(pair["elapsed"]) >= encounter_duration:
            _resolve_pair(key, pair)
            finished.append(key)
    for key in finished:
        _active_pairs.erase(key)

func _scan(agents: Array) -> void:
    var grid: Dictionary = {}
    var valid_agents: Array[VaultCharacterAgent] = []
    for raw in agents:
        if not (raw is VaultCharacterAgent):
            continue
        var agent: VaultCharacterAgent = raw
        if not _eligible(agent):
            continue
        valid_agents.append(agent)
        var key := _cell(agent.global_position)
        if not grid.has(key): grid[key] = []
        grid[key].append(agent)
        agent.set_nearby_witnesses(0)
        if not _active_ids().has(agent.character_id):
            agent.set_social_runtime_context("", agent.global_position, 0, 0.0, 0.0)

    var active_ids := _active_ids()
    var paired_this_scan: Dictionary = active_ids.duplicate()
    last_neighbor_checks = 0
    for agent in valid_agents:
        var origin := _cell(agent.global_position)
        var best: VaultCharacterAgent = null
        var best_d2 := INF
        var nearby := 0
        var checks := 0
        for ox in range(-1, 2):
            for oy in range(-1, 2):
                var bucket = grid.get(origin + Vector2i(ox, oy), [])
                for raw_other in bucket:
                    if checks >= max_neighbor_checks:
                        break
                    var other: VaultCharacterAgent = raw_other
                    if other == agent:
                        continue
                    checks += 1
                    last_neighbor_checks += 1
                    var d2 := agent.global_position.distance_squared_to(other.global_position)
                    if d2 <= approach_radius * approach_radius:
                        nearby += 1
                    if not _social_eligible(agent) or not _social_eligible(other):
                        continue
                    if d2 > approach_radius * approach_radius or d2 >= best_d2:
                        continue
                    var key := _pair_key(agent, other)
                    if _cooldowns.has(key):
                        continue
                    best = other
                    best_d2 = d2
                if checks >= max_neighbor_checks:
                    break
            if checks >= max_neighbor_checks:
                break
        agent.set_nearby_witnesses(nearby)
        if best == null or active_ids.has(agent.character_id):
            continue
        var relation := _relationship(agent, best.character_id)
        agent.set_social_runtime_context(best.character_id, best.global_position, nearby, float(relation.get("affinity", 0.0)), float(relation.get("familiarity", 0.0)))
        if agent.brain.state != "social" or best.brain.state != "social":
            continue
        if best_d2 > encounter_distance * encounter_distance:
            continue
        if paired_this_scan.has(agent.character_id) or paired_this_scan.has(best.character_id):
            continue
        var pair_key := _pair_key(agent, best)
        _active_pairs[pair_key] = {"a": agent, "b": best, "elapsed": 0.0}
        paired_this_scan[agent.character_id] = true
        paired_this_scan[best.character_id] = true

func step(delta: float, agents: Array) -> Dictionary:
    var safe_delta := clampf(delta, 0.0, 2.0)
    _decrement_cooldowns(safe_delta)
    _step_active(safe_delta)
    _scan_elapsed += safe_delta
    if _scan_elapsed >= scan_interval:
        _scan_elapsed = fmod(_scan_elapsed, scan_interval)
        _scan(agents)
    return {
        "active_pairs": _active_pairs.size(),
        "cooldowns": _cooldowns.size(),
        "completed_total": completed_total,
        "neighbor_checks": last_neighbor_checks,
    }
''')

# World runtime integration and fixture semantics bridge.
world_path = "runtime_godot/scripts/world_runtime.gd"
replace_once(world_path, "var navigation_region: NavigationRegion2D\n", "var navigation_region: NavigationRegion2D\nvar social_encounters := VaultSocialEncounterManager.new()\n")
replace_once(
    world_path,
    '    var runtime_interaction: Dictionary = data.get("runtime_interaction", {})\n    agent.apply_runtime_interaction(runtime_interaction)\n',
    '''    var runtime_interaction: Dictionary = data.get("runtime_interaction", {}).duplicate(true)
    var placement_interaction: Dictionary = placement.get("interaction", {})
    if not runtime_interaction.has("interaction_mode"):
        runtime_interaction["interaction_mode"] = str(placement_interaction.get("mode", ""))
    if not runtime_interaction.has("constraint_kind"):
        runtime_interaction["constraint_kind"] = str(placement_interaction.get("fixture_type", current_cell.get("fixture_type", runtime_interaction.get("interaction_mode", ""))))
    agent.apply_runtime_interaction(runtime_interaction)
''',
)
replace_once(
    world_path,
    "func _process(_delta: float) -> void:\n    queue_redraw()\n",
    "func _process(delta: float) -> void:\n    social_encounters.step(delta, agents)\n    queue_redraw()\n",
)

# End-to-end headless harness for emotion + D5 social memory.
write("runtime_godot/scripts/emotion_social_harness.gd", r'''extends SceneTree

func _fail(message: String) -> void:
    push_error("KROLIK_D5_EMOTION_SOCIAL_FAIL %s" % message)
    quit(1)

func _init() -> void:
    var timid := VaultAgentBrain.new()
    timid.apply_snapshot({
        "profile": {"traits": {"boldness": 0.05, "resilience": 0.10, "patience": 0.4}},
        "needs": {"energy": 0.8, "comfort": 0.7, "curiosity": 0.4, "social": 0.4},
    })
    timid.step(1.0, {"bound": true, "interaction_mode": "restrained", "constraint_kind": "shackles", "constraint_severity": 0.95, "constraint_novelty": 0.8, "threat": 0.72, "witnesses": 3})
    var timid_affect := timid.affect_snapshot()

    var defiant := VaultAgentBrain.new()
    defiant.apply_snapshot({
        "profile": {"traits": {"boldness": 0.95, "resilience": 0.95, "patience": 0.2}},
        "needs": {"energy": 0.8, "comfort": 0.7, "curiosity": 0.4, "social": 0.4},
    })
    defiant.step(1.0, {"bound": true, "interaction_mode": "restrained", "constraint_kind": "shackles", "constraint_severity": 0.95, "constraint_novelty": 0.8, "threat": 0.72, "witnesses": 3})
    var defiant_affect := defiant.affect_snapshot()
    if float(timid_affect.get("fear", 0.0)) <= float(defiant_affect.get("fear", 0.0)):
        _fail("personality did not reduce fear")
        return
    if float(defiant_affect.get("anger", 0.0)) <= float(timid_affect.get("anger", 0.0)):
        _fail("bold personality did not redirect reaction toward anger")
        return
    timid.step(0.5, {"released": true, "safe": true})
    if float(timid.affect_snapshot().get("relief", 0.0)) <= 0.25:
        _fail("release did not produce relief")
        return

    var face := VaultFacialState.new()
    face.configure({}, 7)
    if not face.set_mood(str(timid_affect.get("facial_mood", "calm")), 0.9, 0.1):
        _fail("semantic emotion has no facial preset")
        return

    var root := Node2D.new()
    get_root().add_child(root)
    var a := VaultCharacterAgent.new()
    var b := VaultCharacterAgent.new()
    root.add_child(a)
    root.add_child(b)
    a.setup("alice", Vector2(100, 100), {"profile": {"routine": "social", "social": 0.95, "traits": {"sociability": 0.9}}, "needs": {"energy": 0.8, "comfort": 0.8, "curiosity": 0.3, "social": 0.95}})
    b.setup("boris", Vector2(125, 100), {"profile": {"routine": "social", "social": 0.95, "traits": {"sociability": 0.8}}, "needs": {"energy": 0.8, "comfort": 0.8, "curiosity": 0.3, "social": 0.95}})
    a.brain.state = "social"
    b.brain.state = "social"
    var manager := VaultSocialEncounterManager.new()
    manager.scan_interval = 0.1
    manager.encounter_duration = 0.4
    var agents: Array = [a, b]
    for _step in range(12):
        manager.step(0.1, agents)
        a.brain.state = "social"
        b.brain.state = "social"
    if manager.completed_total < 1:
        _fail("close social agents never completed encounter")
        return
    var rel_a := a.relationship_to("boris")
    var rel_b := b.relationship_to("alice")
    if rel_a.is_empty() or rel_b.is_empty():
        _fail("encounter did not enter D4 durable relationship memory")
        return
    if int(rel_a.get("interactions", 0)) < 1 or int(rel_b.get("interactions", 0)) < 1:
        _fail("relationship interaction count missing")
        return
    if manager.last_neighbor_checks > 36:
        _fail("two-agent bounded neighbor budget violated")
        return
    print("KROLIK_D5_EMOTION_SOCIAL status=ok timid_mood=%s timid_fear=%.3f defiant_mood=%s defiant_anger=%.3f encounters=%d affinity_a=%.3f affinity_b=%.3f neighbor_checks=%d" % [str(timid_affect.get("mood", "")), float(timid_affect.get("fear", 0.0)), str(defiant_affect.get("mood", "")), float(defiant_affect.get("anger", 0.0)), manager.completed_total, float(rel_a.get("affinity", 0.0)), float(rel_b.get("affinity", 0.0)), manager.last_neighbor_checks])
    root.free()
    quit(0)
''')

# Permanent focused CI for this capability.
write(".github/workflows/d5-emotion-social.yml", '''name: D5 Emotion Social Runtime

on:
  push:
    branches: [main, work/d5-emotion-encounters-20260915]
    paths:
      - life_sim.py
      - ai_policy.py
      - content/ai/default_policy_v1.json
      - runtime_godot/data/ai_policy_v1.json
      - runtime_godot/scripts/agent_brain.gd
      - runtime_godot/scripts/character_agent.gd
      - runtime_godot/scripts/facial_state.gd
      - runtime_godot/scripts/social_encounter_manager.gd
      - runtime_godot/scripts/emotion_social_harness.gd
      - tests/test_life_sim.py
      - .github/workflows/d5-emotion-social.yml
  pull_request:
    paths:
      - life_sim.py
      - ai_policy.py
      - content/ai/default_policy_v1.json
      - runtime_godot/data/ai_policy_v1.json
      - runtime_godot/scripts/agent_brain.gd
      - runtime_godot/scripts/character_agent.gd
      - runtime_godot/scripts/facial_state.gd
      - runtime_godot/scripts/social_encounter_manager.gd
      - runtime_godot/scripts/emotion_social_harness.gd
      - tests/test_life_sim.py
      - .github/workflows/d5-emotion-social.yml

jobs:
  emotion-social:
    runs-on: ubuntu-latest
    timeout-minutes: 12
    env:
      PYTHONPATH: .
      GODOT_VERSION: 4.7.2
      GODOT_SHA256: cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          cache: pip
      - run: python -m pip install pytest
      - name: Python emotion and policy regressions
        run: |
          python -m py_compile life_sim.py ai_policy.py
          python tools/export_ai_policy.py --check
          pytest -q tests/test_life_sim.py tests/test_ai_policy.py
      - name: Download verified Godot
        shell: bash
        run: |
          set -euo pipefail
          archive="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
          curl --fail --location --retry 4 --output "$archive" "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/${archive}"
          echo "${GODOT_SHA256}  ${archive}" | sha256sum --check --strict
          unzip -q "$archive" -d godot-bin
          chmod +x "godot-bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
      - name: Parse runtime and execute D5 vertical harness
        shell: bash
        run: |
          set -euo pipefail
          GODOT="${GITHUB_WORKSPACE}/godot-bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
          timeout 90s "$GODOT" --headless --path runtime_godot --editor --quit
          timeout 30s "$GODOT" --headless --path runtime_godot --check-only --script res://scripts/social_encounter_manager.gd
          output="${RUNNER_TEMP}/d5-emotion-social.txt"
          timeout 45s "$GODOT" --headless --path runtime_godot --script res://scripts/emotion_social_harness.gd 2>&1 | tee "$output"
          grep -q 'KROLIK_D5_EMOTION_SOCIAL status=ok' "$output"
          if grep -Eq 'KROLIK_D5_EMOTION_SOCIAL_FAIL|SCRIPT ERROR|Parse Error|Failed to load script' "$output"; then exit 1; fi
''')

print("D5 emotion/social patch applied")
