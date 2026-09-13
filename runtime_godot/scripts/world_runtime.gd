extends Node2D

const AgentSceneScript = preload("res://scripts/character_agent.gd")
var agents: Array[VaultCharacterAgent] = []
var world_cells: Dictionary = {}
var world_scale := 0.34
var world_origin := Vector2(90, 80)
var loaded_world_path := ""

func _ready() -> void:
    var user_args := OS.get_cmdline_user_args()
    var requested := ""
    for arg in user_args:
        if arg.begins_with("--world="):
            requested = arg.trim_prefix("--world=")
    if not requested.is_empty() and load_world_snapshot(requested):
        return
    _spawn_diagnostic_world()

func _spawn_diagnostic_world() -> void:
    for i in range(4):
        var a := VaultCharacterAgent.new()
        add_child(a)
        a.setup("demo_%02d" % i, Vector2(260 + i * 180, 360), {"enabled": true,"state": "idle","profile": {"mobility":"free", "autonomy":0.8, "wander":0.75},"needs": {"energy":0.8, "comfort":0.7, "curiosity":0.85 - i * 0.1, "social":0.4}})
        agents.append(a)
    if agents.size() > 2:
        agents[2].contained = true

func _cell_center(cell: Dictionary) -> Vector2:
    var r: Dictionary = cell.get("rect", {})
    return world_origin + Vector2((float(r.get("x", 0.0)) + float(r.get("w", 0.0)) * 0.5) * world_scale,(float(r.get("y", 0.0)) + float(r.get("h", 0.0)) * 0.5) * world_scale)

func load_world_snapshot(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("KROLIK runtime: world snapshot not found: %s" % path)
        return false
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("KROLIK runtime: invalid world JSON")
        return false
    var data: Dictionary = parsed
    if str(data.get("schema", "")) != "krolik.runtime-world/1":
        push_error("KROLIK runtime: unsupported world schema")
        return false
    loaded_world_path = path
    for child in get_children():
        if child is VaultCharacterAgent:
            child.queue_free()
    agents.clear(); world_cells.clear()
    for raw_cell in data.get("cells", []):
        if typeof(raw_cell) != TYPE_DICTIONARY: continue
        var cell: Dictionary = raw_cell
        world_cells[str(cell.get("id", ""))] = cell
    for raw_char in data.get("characters", []):
        if typeof(raw_char) != TYPE_DICTIONARY: continue
        _spawn_snapshot_character(raw_char, path.get_base_dir())
    queue_redraw()
    return true

func _spawn_snapshot_character(data: Dictionary, runtime_root: String) -> void:
    var cid := str(data.get("id", ""))
    var current_cell_id := str(data.get("current_cell_id", data.get("cell_id", "")))
    var home_cell_id := str(data.get("home_cell_id", current_cell_id))
    var current_cell: Dictionary = world_cells.get(current_cell_id, {})
    var home_cell: Dictionary = world_cells.get(home_cell_id, current_cell)
    var spawn := _cell_center(current_cell)
    var package: Dictionary = data.get("runtime_package", {})
    var manifest_path := str(package.get("manifest", ""))
    if manifest_path.is_empty():
        var safe := cid.replace("·", "_")
        manifest_path = runtime_root.path_join(safe).path_join("manifest.json")
    var agent := VaultCharacterAgent.new()
    add_child(agent)
    agent.setup(cid, spawn, {"enabled": true, "state": str(data.get("state", "idle"))})
    agent.home_position = _cell_center(home_cell)
    agent.target_position = spawn
    agent.world_targets = _world_target_points()
    if FileAccess.file_exists(manifest_path): agent.load_runtime_manifest(manifest_path)
    var placement: Dictionary = data.get("placement", {})
    var runtime_interaction: Dictionary = data.get("runtime_interaction", {})
    agent.apply_runtime_interaction(runtime_interaction)
    if runtime_interaction.is_empty():
        agent.contained = str(placement.get("interaction", {}).get("mode", "")) in ["bound", "contained", "anchored", "restrained"]
    agents.append(agent)

func _world_target_points() -> Array[Vector2]:
    var out: Array[Vector2] = []
    for cell in world_cells.values(): out.append(_cell_center(cell))
    return out

func spawn_from_manifest(manifest_path: String, spawn: Vector2) -> VaultCharacterAgent:
    var agent := VaultCharacterAgent.new(); add_child(agent); agent.setup("runtime", spawn, {"enabled": true})
    if not agent.load_runtime_manifest(manifest_path):
        agent.queue_free(); return null
    agent.home_position = spawn; agent.target_position = spawn; agent.world_targets = _world_target_points(); agents.append(agent)
    return agent

func _process(_delta: float) -> void:
    queue_redraw()

func _draw() -> void:
    if world_cells.is_empty():
        draw_rect(Rect2(80, 120, 1120, 500), Color(0.05, 0.055, 0.07, 1.0), true)
        draw_rect(Rect2(80, 120, 1120, 500), Color(0.32, 0.28, 0.25, 1.0), false, 4.0)
        for x in range(5): draw_line(Vector2(170 + x * 220, 140), Vector2(170 + x * 220, 600), Color(0.16,0.15,0.17,1), 2.0)
        return
    for cell in world_cells.values():
        var r: Dictionary = cell.get("rect", {})
        var rect := Rect2(world_origin + Vector2(float(r.get("x", 0.0)), float(r.get("y", 0.0))) * world_scale,Vector2(float(r.get("w", 0.0)), float(r.get("h", 0.0))) * world_scale)
        draw_rect(rect, Color(0.045, 0.05, 0.065, 0.94), true)
        draw_rect(rect, Color(0.22, 0.19, 0.17, 0.95), false, 2.0)
        var fixture := str(cell.get("fixture_type", ""))
        if fixture != "": draw_string(ThemeDB.fallback_font, rect.position + Vector2(8, 18), fixture, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.58,0.54,0.47,0.72))
