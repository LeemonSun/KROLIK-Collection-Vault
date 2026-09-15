class_name VaultSocialEncounterManager
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
