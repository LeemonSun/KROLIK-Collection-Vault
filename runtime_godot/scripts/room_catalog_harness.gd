extends SceneTree

func _fail(message: String) -> void:
    push_error("KROLIK_ROOM_CATALOG_FAIL %s" % message)
    quit(1)

func _init() -> void:
    var catalog := VaultRoomCatalog.new()
    if not catalog.load_default():
        _fail("default room library failed to load")
        return
    var kinds := catalog.kinds()
    if kinds.size() < 14:
        _fail("expected at least 14 room types, got %d" % kinds.size())
        return
    for required in ["stone_cell", "chain_hall", "cage_gallery", "frame_gallery", "quarantine_lab", "deep_vault"]:
        if not catalog.has(required):
            _fail("missing room type %s" % required)
            return
    if catalog.room_kind_for_cell({"room_type": "chain_hall"}) != "chain_hall":
        _fail("cell room_type lookup failed")
        return
    if catalog.room_kind_for_cell({"room_type": "missing"}) != "storage_cell":
        _fail("fallback room lookup failed")
        return
    if catalog.capacity("archive_gallery") != 6:
        _fail("archive capacity mismatch")
        return
    if catalog.placement_slots("chain_hall").size() < 6:
        _fail("chain hall placement slots missing")
        return
    if "hanging_chains" not in catalog.preferred_fixture_kinds("chain_hall"):
        _fail("chain hall fixture compatibility missing")
        return
    if catalog.builtin_fixtures("cage_gallery").size() < 3:
        _fail("cage gallery builtins missing")
        return

    var distinct: Dictionary = {}
    var slot_count := 0
    for kind in kinds:
        var theme := catalog.theme(kind)
        var floor = theme.get("floor_rgb", [])
        distinct[JSON.stringify(floor)] = true
        slot_count += catalog.placement_slots(kind).size()
    if distinct.size() < 10:
        _fail("room visuals are not varied enough")
        return
    if slot_count < 50:
        _fail("room placement slot coverage too small: %d" % slot_count)
        return

    print("KROLIK_ROOM_CATALOG status=ok rooms=%d themes=%d slots=%d revision=%d" % [kinds.size(), distinct.size(), slot_count, catalog.revision])
    quit(0)
