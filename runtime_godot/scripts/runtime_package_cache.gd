class_name VaultRuntimePackageCache
extends RefCounted

## Process-local cache for sealed runtime packages.
##
## Runtime package manifests and character textures are immutable derived assets.
## Repeated characters may safely share the decoded Texture2D while callers get a
## deep copy of the manifest document so per-agent runtime configuration can never
## mutate cached canonical data.
##
## Entries are invalidated when either the manifest or referenced image mtime or
## size changes. The cache never changes package files or their versioned schema.

static var _entries: Dictionary = {}
static var _manifest_parses := 0
static var _texture_decodes := 0
static var _cache_hits := 0
static var _cache_misses := 0
static var _invalidations := 0

static func reset_cache() -> void:
    _entries.clear()
    _manifest_parses = 0
    _texture_decodes = 0
    _cache_hits = 0
    _cache_misses = 0
    _invalidations = 0

static func stats_snapshot() -> Dictionary:
    return {
        "entries": _entries.size(),
        "manifest_parses": _manifest_parses,
        "texture_decodes": _texture_decodes,
        "hits": _cache_hits,
        "misses": _cache_misses,
        "invalidations": _invalidations,
    }

static func _file_stamp(path: String) -> Dictionary:
    if path.is_empty() or not FileAccess.file_exists(path):
        return {}
    return {
        "mtime": int(FileAccess.get_modified_time(path)),
        "size": int(FileAccess.get_size(path)),
    }

static func _same_stamp(a: Variant, b: Variant) -> bool:
    if typeof(a) != TYPE_DICTIONARY or typeof(b) != TYPE_DICTIONARY:
        return false
    return int(a.get("mtime", -1)) == int(b.get("mtime", -2)) and int(a.get("size", -1)) == int(b.get("size", -2))

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
            var hit := _cached_result(existing)
            if not hit.is_empty():
                _cache_hits += 1
                return hit
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

    var image := Image.new()
    if image.load(image_path) != OK:
        return {}
    var texture := ImageTexture.create_from_image(image)
    if texture == null:
        return {}
    _texture_decodes += 1

    var canonical_manifest := manifest.duplicate(true)
    var entry := {
        "manifest_stamp": manifest_stamp,
        "image_stamp": image_stamp,
        "manifest": canonical_manifest,
        "image_path": image_path,
        "texture": texture,
    }
    _entries[clean_path] = entry
    return _cached_result(entry)
