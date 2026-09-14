class_name VaultAgentBrainRuntime
extends VaultAgentBrain

## Production extension of the policy-driven brain with bounded long-term affinity.
## Affinity lookups are O(1); slow decay is materialized at most once per minute
## or immediately before an event/snapshot so 200–500 live agents stay cheap.

const AFFINITY_MATERIALIZE_HOURS := 1.0 / 60.0

var affinity_state := VaultAffinityState.new()
var _affinity_elapsed_hours := 0.0

func _init() -> void:
    super()
    affinity_state.configure(_section("long_term_affinity"))

func _materialize_affinity() -> void:
    if _affinity_elapsed_hours <= 0.0:
        return
    affinity_state.decay(_affinity_elapsed_hours)
    _affinity_elapsed_hours = 0.0

func apply_snapshot(data: Dictionary) -> void:
    super(data)
    affinity_state.configure(_section("long_term_affinity"))
    affinity_state.apply_snapshot(data.get("affinity", []))
    _affinity_elapsed_hours = 0.0

func activity_scores(context: Dictionary = {}) -> Dictionary:
    var scores := super(context)
    var bias := affinity_state.utility_bias(context)
    for state_name in bias.keys():
        if scores.has(state_name):
            scores[state_name] = float(scores[state_name]) + float(bias[state_name])
    return scores

func step(delta: float, context_value: Variant = {}) -> String:
    _affinity_elapsed_hours += clampf(delta, 0.0, 300.0) / 3600.0
    if _affinity_elapsed_hours >= AFFINITY_MATERIALIZE_HOURS:
        _materialize_affinity()
    return super(delta, context_value)

func learn_affinity(kind: String, subject: String, signal: float) -> bool:
    _materialize_affinity()
    return affinity_state.learn(kind, subject, signal)

func affinity_snapshot() -> Array:
    _materialize_affinity()
    return affinity_state.snapshot()

func favorite_place() -> String:
    _materialize_affinity()
    return affinity_state.favorite_place()

func snapshot() -> Dictionary:
    _materialize_affinity()
    var out := super()
    out["affinity"] = affinity_state.snapshot()
    out["favorite_place"] = affinity_state.favorite_place()
    return out
