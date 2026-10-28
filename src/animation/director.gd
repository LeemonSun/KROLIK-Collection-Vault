extends RefCounted
## Schedules reviewed animation resources. It does not generate or render motion.
signal animation_requested(layer, event_id, animation)
signal animation_stopped(layer, event_id)

const LAYERS = ["body", "face", "gaze"]
const QUALITY_KEYS = ["identity", "silhouette", "contacts", "secondary_motion", "face", "transitions", "low_fps"]
var events = {}
var clips = {}
var active = {}
var cooldowns = {}
var paused = false
var reduced_motion = false
var last_time_ms = -1
var character_id = ""
var design_revision = ""
var expected_rig_revision = ""
var allowed_resource_root = "res://assets/characters/leemon_01/runtime/"

func configure(catalog, resource_root = "res://assets/characters/leemon_01/runtime/"):
	if not catalog is Dictionary or catalog.get("schema_version") != 1:
		return false
	if not catalog.get("events") is Array or str(catalog.get("character_id", "")).is_empty() or str(catalog.get("design_revision", "")).is_empty() or str(catalog.get("expected_rig_revision", "")).is_empty():
		return false
	var next_events = {}
	for item in catalog.get("events", []):
		if not item is Dictionary:
			return false
		var id = item.get("id", "")
		if not id is String or id.is_empty() or next_events.has(id):
			return false
		if item.get("layer") not in LAYERS or not item.get("clip_id", "") is String:
			return false
		if not item.get("priority") is float and not item.get("priority") is int:
			return false
		if not is_finite(float(item.priority)) or item.priority < 0 or item.priority > 100:
			return false
		if not item.get("duration_ms") is float and not item.get("duration_ms") is int:
			return false
		if not is_finite(float(item.duration_ms)) or item.duration_ms < 1 or item.duration_ms > 30000:
			return false
		if not item.get("cooldown_ms") is float and not item.get("cooldown_ms") is int:
			return false
		if not is_finite(float(item.cooldown_ms)) or item.cooldown_ms < 0 or item.cooldown_ms > 60000:
			return false
		if not item.get("loop") is bool or not item.get("interruptible") is bool:
			return false
		next_events[id] = item.duplicate(true)
	for id in next_events:
		var fallback = next_events[id].get("reduced_motion_fallback", "")
		if not fallback is String or (not fallback.is_empty() and not next_events.has(fallback)):
			return false
		var seen = {}
		var cursor = id
		while not cursor.is_empty():
			if seen.has(cursor):
				return false
			seen[cursor] = true
			cursor = next_events[cursor].get("reduced_motion_fallback", "")
	if not resource_root.begins_with("res://") and not resource_root.begins_with("user://"):
		return false
	clear()
	events = next_events
	clips.clear()
	cooldowns.clear()
	last_time_ms = -1
	character_id = str(catalog.get("character_id", ""))
	design_revision = str(catalog.get("design_revision", ""))
	expected_rig_revision = str(catalog.get("expected_rig_revision", ""))
	allowed_resource_root = resource_root.trim_suffix("/") + "/"
	return not character_id.is_empty() and not expected_rig_revision.is_empty()

func install_bundle(bundle):
	# Internal asset-pipeline API, never a tool exposed to the language model.
	if not bundle is Dictionary or bundle.get("schema_version") != 1:
		return {"ok": false, "reason": "bundle_invalid"}
	if bundle.get("character_id") != character_id or bundle.get("design_revision") != design_revision or bundle.get("rig_revision") != expected_rig_revision:
		return {"ok": false, "reason": "identity_mismatch"}
	if bundle.get("review_status") != "approved":
		return {"ok": false, "reason": "bundle_not_reviewed"}
	if not bundle.get("clips") is Array:
		return {"ok": false, "reason": "bundle_invalid"}
	var next_clips = {}
	var known_ids = {}
	for event in events.values():
		known_ids[event.clip_id] = true
	for item in bundle.get("clips", []):
		if not item is Dictionary:
			return {"ok": false, "reason": "clip_invalid"}
		var id = str(item.get("id", ""))
		var path = str(item.get("resource", ""))
		if not known_ids.has(id) or next_clips.has(id):
			return {"ok": false, "reason": "clip_id_invalid"}
		if item.get("review_status") != "approved" or item.get("rights_status") not in ["owned", "licensed"]:
			return {"ok": false, "reason": "clip_not_reviewed"}
		var quality = item.get("quality", {})
		if not quality is Dictionary:
			return {"ok": false, "reason": "quality_missing"}
		for key in QUALITY_KEYS:
			if quality.get(key) != true:
				return {"ok": false, "reason": "quality_missing"}
		if not path.begins_with(allowed_resource_root) or path.contains("..") or path.get_extension() != "tres" or not FileAccess.file_exists(path):
			return {"ok": false, "reason": "resource_invalid"}
		var digest = str(item.get("sha256", ""))
		if digest.length() != 64 or FileAccess.get_sha256(path) != digest:
			return {"ok": false, "reason": "hash_mismatch"}
		# Only Animation resources, never scenes or script-bearing resources.
		var resource = ResourceLoader.load(path, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
		if not resource is Animation or resource.get_script() != null or resource.get_track_count() == 0:
			return {"ok": false, "reason": "animation_invalid"}
		for track in range(resource.get_track_count()):
			if resource.track_get_type(track) not in [Animation.TYPE_VALUE, Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D, Animation.TYPE_BLEND_SHAPE]:
				return {"ok": false, "reason": "animation_track_denied"}
		next_clips[id] = resource
	clear()
	clips = next_clips
	return {"ok": true, "count": clips.size()}

func request(event_id, now_ms):
	if not _valid_time(now_ms):
		return {"ok": false, "reason": "time_invalid"}
	tick(now_ms)
	if paused:
		return {"ok": false, "reason": "paused"}
	if not events.has(event_id):
		return {"ok": false, "reason": "event_unknown"}
	var selected = event_id
	if reduced_motion:
		while not events[selected].get("reduced_motion_fallback", "").is_empty():
			selected = events[selected].reduced_motion_fallback
	var spec = events[selected]
	if not clips.has(spec.clip_id):
		return {"ok": false, "reason": "asset_missing", "event_id": selected}
	if animation_requested.get_connections().is_empty():
		return {"ok": false, "reason": "renderer_missing", "event_id": selected}
	var layer = spec.layer
	if active.has(layer):
		var running = active[layer]
		if running.id == selected and spec.loop:
			return {"ok": true, "reason": "coalesced", "event_id": selected}
		if not running.interruptible or int(spec.priority) < running.priority:
			return {"ok": false, "reason": "busy", "event_id": selected}
	if now_ms < cooldowns.get(selected, -1):
		return {"ok": false, "reason": "cooldown", "event_id": selected}
	if active.has(layer):
		_stop(layer)
	active[layer] = {"id": selected, "priority": int(spec.priority), "interruptible": spec.interruptible,
		"until_ms": -1 if spec.loop else now_ms + int(spec.duration_ms)}
	cooldowns[selected] = now_ms + int(spec.cooldown_ms)
	animation_requested.emit(layer, selected, clips[spec.clip_id])
	return {"ok": true, "reason": "dispatched", "event_id": selected}

func tick(now_ms):
	if not _valid_time(now_ms):
		return false
	last_time_ms = now_ms
	for layer in active.keys():
		var deadline = active[layer].until_ms
		if deadline >= 0 and now_ms >= deadline:
			_stop(layer)
	return true

func _valid_time(now_ms):
	return now_ms is int and now_ms >= 0 and now_ms >= last_time_ms

func _stop(layer):
	var id = active[layer].id
	active.erase(layer)
	animation_stopped.emit(layer, id)

func clear():
	for layer in active.keys():
		_stop(layer)

func set_paused(value):
	paused = bool(value)
	if paused:
		clear()

func set_reduced_motion(value):
	var next = bool(value)
	if next != reduced_motion:
		clear()
	reduced_motion = next

func summary():
	return {"character_id": character_id, "planned_events": events.size(), "installed_clips": clips.size(),
		"active_layers": active.size(), "renderer_bound": not animation_requested.get_connections().is_empty()}
