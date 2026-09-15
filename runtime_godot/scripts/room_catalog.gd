class_name VaultRoomCatalog
extends RefCounted

const DEFAULT_PATH := "res://data/rooms_v1.json"
const ROOM_SCHEMA := "krolik.room-library/1"

var document: Dictionary = {}
var rooms: Dictionary = {}
var source_path := ""
var revision := 0

func load_default() -> bool:
    return load_path(DEFAULT_PATH)

func load_path(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("KROLIK room catalog: unable to open %s" % path)
        return false
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("KROLIK room catalog: root must be an object")
        return false
    var candidate: Dictionary = parsed
    if str(candidate.get("schema", "")) != ROOM_SCHEMA:
        push_error("KROLIK room catalog: unsupported schema")
        return false
    if int(candidate.get("format_version", 0)) != 1:
        push_error("KROLIK room catalog: unsupported format version")
        return false
    var raw_rooms = candidate.get("rooms", {})
    if typeof(raw_rooms) != TYPE_DICTIONARY or raw_rooms.is_empty():
        push_error("KROLIK room catalog: rooms missing")
        return false
    for raw_kind in raw_rooms.keys():
        var kind := str(raw_kind)
        var room = raw_rooms[raw_kind]
        if kind.is_empty() or typeof(room) != TYPE_DICTIONARY:
            push_error("KROLIK room catalog: malformed room %s" % kind)
            return false
        var theme = room.get("theme", {})
        var slots = room.get("placement_slots", [])
        if typeof(theme) != TYPE_DICTIONARY or typeof(slots) != TYPE_ARRAY:
            push_error("KROLIK room catalog: malformed theme/slots for %s" % kind)
            return false
    document = candidate.duplicate(true)
    rooms = raw_rooms.duplicate(true)
    source_path = path
    revision += 1
    return true

func kinds() -> Array[String]:
    var out: Array[String] = []
    for raw in rooms.keys():
        out.append(str(raw))
    out.sort()
    return out

func has(kind: String) -> bool:
    return rooms.has(kind)

func get_room(kind: String) -> Dictionary:
    var room = rooms.get(kind, {})
    return room.duplicate(true) if typeof(room) == TYPE_DICTIONARY else {}

func fallback_kind() -> String:
    if rooms.has("storage_cell"):
        return "storage_cell"
    var all := kinds()
    return all[0] if not all.is_empty() else ""

func room_kind_for_cell(cell: Dictionary) -> String:
    var requested := str(cell.get("room_type", cell.get("type", "")))
    if rooms.has(requested):
        return requested
    return fallback_kind()

func theme(kind: String) -> Dictionary:
    var room := get_room(kind)
    var value = room.get("theme", {})
    return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}

func theme_color(kind: String, key: String, fallback: Color) -> Color:
    var value = theme(kind).get(key, null)
    if typeof(value) != TYPE_ARRAY or value.size() != 3:
        return fallback
    return Color(
        clampf(float(value[0]), 0.0, 1.0),
        clampf(float(value[1]), 0.0, 1.0),
        clampf(float(value[2]), 0.0, 1.0),
        fallback.a
    )

func capacity(kind: String) -> int:
    return maxi(1, int(get_room(kind).get("capacity", 1)))

func placement_slots(kind: String) -> Array:
    var value = get_room(kind).get("placement_slots", [])
    return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []

func preferred_fixture_kinds(kind: String) -> Array[String]:
    var out: Array[String] = []
    var room := get_room(kind)
    var compatibility = room.get("fixture_compatibility", {})
    if typeof(compatibility) != TYPE_DICTIONARY:
        return out
    var preferred = compatibility.get("preferred_fixture_kinds", [])
    if typeof(preferred) != TYPE_ARRAY:
        return out
    for raw in preferred:
        out.append(str(raw))
    return out

func builtin_fixtures(kind: String) -> Array:
    var value = get_room(kind).get("builtins", [])
    return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []
