extends Node2D

const AgentSceneScript = preload("res://scripts/character_agent.gd")
var agents: Array[VaultCharacterAgent] = []
var world_cells: Dictionary = {}
var world_scale := 0.34
var world_origin := Vector2(90, 80)
var loaded_world_path := ""
var navigation_region: NavigationRegion2D
var social_encounters := VaultSocialEncounterManager.new()
var room_catalog := VaultRoomCatalog.new()

func _ready() -> void:
    if not room_catalog.load_default():
        push_error("KROLIK runtime: room catalog unavailable; room rendering will use fallback colors")
    var user_args := OS.get_cmdline_user_args()
    var requested := ""
    for arg in user_args:
        if arg.begins_with("--world="):
            requested = arg.trim_prefix("--world=")
    if not requested.is_empty() and load_world_snapshot(requested):
        return
    _spawn_diagnostic_world()

func _spawn_diagnostic_world() -> void:
    world_cells.clear()
    var room_types := ["stone_cell", "chain_hall", "cage_gallery", "frame_gallery", "quarantine_lab"]
    var fixtures := ["wall_cuffs", "hanging_chains", "standing_cage", "x_frame", "display_frame"]
    for i in range(room_types.size()):
        var cell_id := "demo_room_%02d" % i
        world_cells[cell_id] = {
            "id": cell_id,
            "room_type": room_types[i],
            "fixture_type": fixtures[i],
            "rect": {"x": float(i * 610), "y": 110.0, "w": 570.0, "h": 920.0},
        }
    _rebuild_navigation()
    for i in range(4):
        var a := VaultCharacterAgent.new()
        add_child(a)
        var cell: Dictionary = world_cells["demo_room_%02d" % i]
        var spawn := _cell_center(cell)
        a.setup("demo_%02d" % i, spawn, {
            "enabled": true,
            "state": "idle",
            "profile": {"mobility":"free", "autonomy":0.8, "wander":0.75},
            "needs": {"energy":0.8, "comfort":0.7, "curiosity":0.85 - i * 0.1, "social":0.4}
        })
        a.home_position = spawn
        a.target_position = spawn
        agents.append(a)
    var targets := _world_target_points()
    for agent in agents:
        agent.world_targets = targets
    if agents.size() > 2:
        agents[2].contained = true
        agents[2].apply_runtime_interaction({
            "contained": true,
            "interaction_mode": "contained",
            "constraint_kind": "cage",
            "constraint_severity": 0.72,
        })

func _cell_center(cell: Dictionary) -> Vector2:
    var r: Dictionary = cell.get("rect", {})
    return world_origin + Vector2(
        (float(r.get("x", 0.0)) + float(r.get("w", 0.0)) * 0.5) * world_scale,
        (float(r.get("y", 0.0)) + float(r.get("h", 0.0)) * 0.5) * world_scale
    )

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
    agents.clear()
    world_cells.clear()
    for raw_cell in data.get("cells", []):
        if typeof(raw_cell) != TYPE_DICTIONARY:
            continue
        var cell: Dictionary = raw_cell
        world_cells[str(cell.get("id", ""))] = cell
    _rebuild_navigation()
    for raw_char in data.get("characters", []):
        if typeof(raw_char) != TYPE_DICTIONARY:
            continue
        _spawn_snapshot_character(raw_char, path.get_base_dir())
    queue_redraw()
    return true

func _clear_navigation() -> void:
    if navigation_region != null and is_instance_valid(navigation_region):
        remove_child(navigation_region)
        navigation_region.queue_free()
        navigation_region = null

func _build_navigation_from_rect(rect: Rect2) -> void:
    _clear_navigation()
    if rect.size.x <= 1.0 or rect.size.y <= 1.0:
        return
    navigation_region = NavigationRegion2D.new()
    navigation_region.name = "VaultNavigation"
    var nav_poly := NavigationPolygon.new()
    nav_poly.vertices = PackedVector2Array([
        rect.position,
        rect.position + Vector2(rect.size.x, 0),
        rect.position + rect.size,
        rect.position + Vector2(0, rect.size.y),
    ])
    nav_poly.add_polygon(PackedInt32Array([0, 1, 2, 3]))
    navigation_region.navigation_polygon = nav_poly
    add_child(navigation_region)

func _rebuild_navigation() -> void:
    if world_cells.is_empty():
        _build_navigation_from_rect(Rect2(80, 120, 1120, 500))
        return
    var first := true
    var bounds := Rect2()
    for cell in world_cells.values():
        var r: Dictionary = cell.get("rect", {})
        var rect := Rect2(
            world_origin + Vector2(float(r.get("x", 0.0)), float(r.get("y", 0.0))) * world_scale,
            Vector2(float(r.get("w", 0.0)), float(r.get("h", 0.0))) * world_scale
        )
        if first:
            bounds = rect
            first = false
        else:
            bounds = bounds.merge(rect)
    bounds = bounds.grow(18.0)
    _build_navigation_from_rect(bounds)

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
    if FileAccess.file_exists(manifest_path):
        agent.load_runtime_manifest(manifest_path)
    var placement: Dictionary = data.get("placement", {})
    var runtime_interaction: Dictionary = data.get("runtime_interaction", {}).duplicate(true)
    var placement_interaction: Dictionary = placement.get("interaction", {})
    if not runtime_interaction.has("interaction_mode"):
        runtime_interaction["interaction_mode"] = str(placement_interaction.get("mode", ""))
    if not runtime_interaction.has("constraint_kind"):
        runtime_interaction["constraint_kind"] = str(placement_interaction.get("fixture_type", current_cell.get("fixture_type", runtime_interaction.get("interaction_mode", ""))))
    agent.apply_runtime_interaction(runtime_interaction)
    if runtime_interaction.is_empty():
        agent.contained = str(placement.get("interaction", {}).get("mode", "")) in ["bound", "contained", "anchored", "restrained"]
    agents.append(agent)

func _world_target_points() -> Array[Vector2]:
    var out: Array[Vector2] = []
    for cell in world_cells.values():
        out.append(_cell_center(cell))
    return out

func spawn_from_manifest(manifest_path: String, spawn: Vector2) -> VaultCharacterAgent:
    var agent := VaultCharacterAgent.new()
    add_child(agent)
    agent.setup("runtime", spawn, {"enabled": true})
    if not agent.load_runtime_manifest(manifest_path):
        agent.queue_free()
        return null
    agent.home_position = spawn
    agent.target_position = spawn
    agent.world_targets = _world_target_points()
    agents.append(agent)
    return agent

func _process(delta: float) -> void:
    social_encounters.step(delta, agents)
    queue_redraw()

func _room_rect(cell: Dictionary) -> Rect2:
    var r: Dictionary = cell.get("rect", {})
    return Rect2(
        world_origin + Vector2(float(r.get("x", 0.0)), float(r.get("y", 0.0))) * world_scale,
        Vector2(float(r.get("w", 0.0)), float(r.get("h", 0.0))) * world_scale
    )

func _draw_room_slots(rect: Rect2, room_kind: String, accent: Color) -> void:
    if room_catalog.rooms.is_empty():
        return
    for raw_slot in room_catalog.placement_slots(room_kind):
        if typeof(raw_slot) != TYPE_DICTIONARY:
            continue
        var slot: Dictionary = raw_slot
        var point := rect.position + Vector2(
            rect.size.x * clampf(float(slot.get("x", 0.5)), 0.0, 1.0),
            rect.size.y * clampf(float(slot.get("y", 0.5)), 0.0, 1.0)
        )
        var role := str(slot.get("role", "character"))
        var radius := 2.6 if role == "fixture" else 2.0
        var marker := Color(accent.r, accent.g, accent.b, 0.28 if role == "fixture" else 0.18)
        draw_circle(point, radius, marker)

func _draw() -> void:
    if world_cells.is_empty():
        draw_rect(Rect2(80, 120, 1120, 500), Color(0.05, 0.055, 0.07, 1.0), true)
        draw_rect(Rect2(80, 120, 1120, 500), Color(0.32, 0.28, 0.25, 1.0), false, 4.0)
        return
    for cell in world_cells.values():
        var rect := _room_rect(cell)
        var room_kind := room_catalog.room_kind_for_cell(cell) if not room_catalog.rooms.is_empty() else "storage_cell"
        var fill := room_catalog.theme_color(room_kind, "floor_rgb", Color(0.045, 0.05, 0.065, 0.94))
        fill.a = 0.96
        var border := room_catalog.theme_color(room_kind, "border_rgb", Color(0.22, 0.19, 0.17, 0.95))
        border.a = 0.96
        var accent := room_catalog.theme_color(room_kind, "accent_rgb", Color(0.58, 0.54, 0.47, 0.72))
        accent.a = 0.72
        draw_rect(rect, fill, true)
        draw_rect(rect, border, false, 2.0)
        draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3.0)), Color(accent.r, accent.g, accent.b, 0.42), true)
        _draw_room_slots(rect, room_kind, accent)
        draw_string(
            ThemeDB.fallback_font,
            rect.position + Vector2(8, 18),
            room_kind.replace("_", " ").to_upper(),
            HORIZONTAL_ALIGNMENT_LEFT,
            -1,
            10,
            Color(accent.r, accent.g, accent.b, 0.80)
        )
        var fixture := str(cell.get("fixture_type", ""))
        if fixture != "":
            draw_string(
                ThemeDB.fallback_font,
                rect.position + Vector2(8, 34),
                fixture.replace("_", " "),
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                9,
                Color(border.r, border.g, border.b, 0.72)
            )
