class_name VaultRuntimePackageCache
extends RefCounted

## Process-local cache for sealed runtime packages.
##
## Runtime package manifests and character textures are immutable derived assets.
## Repeated characters may safely share the decoded Texture2D while callers get a
## deep copy of the manifest document so per-agent runtime configuration can never
## mutate cached canonical data.
##
## Manifest metadata is cheap and stays cached for every package seen in the
## process. Full decoded textures are intentionally bounded by an LRU limit so a
## Vault containing hundreds of unique sleeping characters cannot pin hundreds of
## full-resolution Texture2D resources. Evicting a cache reference is safe: active
## agents keep their own RefCounted Texture2D reference and continue rendering.
## A later request for an evicted package simply re-decodes its immutable image.
##
## Entries are invalidated when either the manifest or referenced image mtime or
## size changes. The cache never changes package files or their versioned schema.

const DEFAULT_TEXTURE_CACHE_LIMIT := 96
const MIN_TEXTURE_CACHE_LIMIT := 8
const MAX_TEXTURE_CACHE_LIMIT := 1024

static var _entries: Dictionary = {}
static var _manifest_parses := 0
static var _texture_decodes := 0
static var _cache_hits := 0
static var _cache_misses := 0
static var _invalidations := 0
static var _texture_evictions := 0
static var _access_tick := 0

static func reset_cache() -> void:
    _entries.clear()
    _manifest_parses = 0
    _texture_decodes = 0
    _cache_hits = 0
    _cache_misses = 0
    _invalidations = 0
    _texture_evictions = 0
    _access_tick = 0

static func _texture_cache_limit() -> int:
    var raw := OS.get_environment("KROLIK_RUNTIME_TEXTURE_CACHE_LIMIT").strip_edges()
    if raw.is_empty() or not raw.is_valid_int():
        return DEFAULT_TEXTURE_CACHE_LIMIT
    return clampi(int(raw), MIN_TEXTURE_CACHE_LIMIT, MAX_TEXTURE_CACHE_LIMIT)

static func _texture_entry_count() -> int:
    var count := 0
    for value in _entries.values():
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = value
        if entry.get("texture", null) != null:
            count += 1
    return count

static func stats_snapshot() -> Dictionary:
    return {
        "entries": _entries.size(),
        "texture_entries": _texture_entry_count(),
        "texture_limit": _texture_cache_limit(),
        "manifest_parses": _manifest_parses,
        "texture_decodes": _texture_decodes,
        "texture_evictions": _texture_evictions,
        "hits": _cache_hits,
        "misses": _cache_misses,
        "invalidations": _invalidations,
    }

static func _file_stamp(path: String) -> Dictionary:
    if path.is_empty() or not FileAccess.file_exists(path):
        return {}
    var handle := FileAccess.open(path, FileAccess.READ)
    if handle == null:
        return {}
    var size := handle.get_length()
    handle.close()
    return {
        "mtime": int(FileAccess.get_modified_time(path)),
        "size": int(size),
    }

static func _same_stamp(a: Variant, b: Variant) -> bool:
    if typeof(a) != TYPE_DICTIONARY or typeof(b) != TYPE_DICTIONARY:
        return false
    return int(a.get("mtime", -1)) == int(b.get("mtime", -2)) and int(a.get("size", -1)) == int(b.get("size", -2))

static func _next_tick() -> int:
    _access_tick += 1
    return _access_tick

static func _decode_texture(entry: Dictionary) -> Texture2D:
    var image_path := str(entry.get("image_path", ""))
    if image_path.is_empty() or not FileAccess.file_exists(image_path):
        return null
    var image := Image.new()
    if image.load(image_path) != OK:
        return null
    var texture := ImageTexture.create_from_image(image)
    if texture == null:
        return null
    _texture_decodes += 1
    entry["texture"] = texture
    entry["texture_access_tick"] = _next_tick()
    return texture

static func _touch_texture(entry: Dictionary) -> void:
    if entry.get("texture", null) != null:
        entry["texture_access_tick"] = _next_tick()

static func _trim_texture_cache(protected_path: String = "") -> void:
    var limit := _texture_cache_limit()
    while _texture_entry_count() > limit:
        var oldest_path := ""
        var oldest_tick := 9223372036854775807
        for path_value in _entries.keys():
            var path := str(path_value)
            if path == protected_path:
                continue
            var entry_value: Variant = _entries[path_value]
            if typeof(entry_value) != TYPE_DICTIONARY:
                continue
            var entry: Dictionary = entry_value
            if entry.get("texture", null) == null:
                continue
            var tick := int(entry.get("texture_access_tick", 0))
            if oldest_path.is_empty() or tick < oldest_tick:
                oldest_path = path
                oldest_tick = tick
        if oldest_path.is_empty():
            # The only remaining texture can be the protected just-returned one.
            # Keeping one entry above a pathological limit is safer than returning
            # a texture after dropping the cache's only reference mid-call.
            break
        var oldest_value: Variant = _entries.get(oldest_path, null)
        if typeof(oldest_value) != TYPE_DICTIONARY:
            break
        var oldest: Dictionary = oldest_value
        oldest["texture"] = null
        oldest["texture_access_tick"] = 0
        _entries[oldest_path] = oldest
        _texture_evictions += 1

static func _cached_result(entry: Dictionary) -> Dictionary:
    var manifest_value: Variant = entry.get("manifest", {})
    var texture_value: Variant = entry.get("texture", null)
    if typeof(manifest_value) != TYPE_DICTIONARY or texture_value == null:
        return {}
    var manifest: Dictionary = manifest_value
    return {
        "manifest": manifest.duplicate(true),
        "texture": texture_value,
        "image_path": str(entry.get("image_path", "")),
    }

static func load_package(manifest_path: String) -> Dictionary:
    var clean_path := manifest_path.strip_edges()
    if clean_path.is_empty() or not FileAccess.file_exists(clean_path):
        return {}

    var manifest_stamp := _file_stamp(clean_path)
    var existing_value: Variant = _entries.get(clean_path, null)
    if typeof(existing_value) == TYPE_DICTIONARY:
        var existing: Dictionary = existing_value
        var image_path := str(existing.get("image_path", ""))
        var image_stamp := _file_stamp(image_path)
        if _same_stamp(existing.get("manifest_stamp", {}), manifest_stamp) and _same_stamp(existing.get("image_stamp", {}), image_stamp):
            var texture: Texture2D = existing.get("texture", null) as Texture2D
            if texture == null:
                texture = _decode_texture(existing)
                if texture == null:
                    return {}
                _entries[clean_path] = existing
            else:
                _touch_texture(existing)
                _entries[clean_path] = existing
            _cache_hits += 1
            _trim_texture_cache(clean_path)
            return _cached_result(existing)
        _entries.erase(clean_path)
        _invalidations += 1

    _cache_misses += 1
    var file := FileAccess.open(clean_path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    _manifest_parses += 1
    var manifest: Dictionary = parsed
    var visual_value: Variant = manifest.get("visual", {})
    if typeof(visual_value) != TYPE_DICTIONARY:
        return {}
    var visual: Dictionary = visual_value
    var image_name := str(visual.get("file", "character.png")).strip_edges()
    if image_name.is_empty():
        return {}
    var image_path := clean_path.get_base_dir().path_join(image_name)
    var image_stamp := _file_stamp(image_path)
    if image_stamp.is_empty():
        return {}

    var canonical_manifest := manifest.duplicate(true)
    var entry := {
        "manifest_stamp": manifest_stamp,
        "image_stamp": image_stamp,
        "manifest": canonical_manifest,
        "image_path": image_path,
        "texture": null,
        "texture_access_tick": 0,
    }
    var texture := _decode_texture(entry)
    if texture == null:
        return {}
    _entries[clean_path] = entry
    _trim_texture_cache(clean_path)
    return _cached_result(entry)
