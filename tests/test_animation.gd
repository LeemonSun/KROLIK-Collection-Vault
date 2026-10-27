extends SceneTree
const Director = preload("res://src/animation/director.gd")
var checks = 0
var failures = []

func _initialize():
	_run.call_deferred()

func check(value, message):
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _fixture_animation(path, kind = Animation.TYPE_VALUE):
	var animation = Animation.new()
	animation.length = 1.0
	if kind >= 0:
		var track = animation.add_track(kind)
		animation.track_set_path(track, NodePath(".:value"))
		if kind == Animation.TYPE_VALUE:
			animation.track_insert_key(track, 0.0, 0.0)
			animation.track_insert_key(track, 1.0, 1.0)
	ResourceSaver.save(animation, path)
	return animation

func _run():
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://manifests/animation_catalog.json"))
	var d = Director.new()
	check(d.configure(catalog), "Production catalog accepted")
	check(d.summary().planned_events == 113, "113 distinct production scenarios")
	check(d.summary().installed_clips == 0, "Plans never count as finished clips")
	check(d.request("locomotion.red_dash", 0).reason == "asset_missing", "No fake movement without clip")
	var empty_pack = JSON.parse_string(FileAccess.get_file_as_string("res://manifests/animation_pack.json"))
	check(not d.install_bundle(empty_pack).ok, "Unproduced rig cannot be installed")
	var fixture_root = "user://animation-fixture-%s/" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_root))
	var normal_path = fixture_root + "value.tres"
	var method_path = fixture_root + "method.tres"
	var empty_path = fixture_root + "empty.tres"
	_fixture_animation(normal_path)
	_fixture_animation(method_path, Animation.TYPE_METHOD)
	_fixture_animation(empty_path, -1)
	check(d.configure(catalog, fixture_root), "Isolated fixture root")
	var events_to_install = ["idle.relaxed", "work.progress", "work.success_proud", "interaction.pickup", "emotion.smile_warm", "transition.fade", "locomotion.red_dash"]
	var quality = {}
	for key in Director.QUALITY_KEYS:
		quality[key] = true
	var bundle = {"schema_version": 1, "character_id": "signal_01", "design_revision": "v1", "rig_revision": "signal_01_rig_v1", "review_status": "approved", "clips": []}
	for id in events_to_install:
		bundle.clips.append({"id": d.events[id].clip_id, "resource": normal_path, "sha256": FileAccess.get_sha256(normal_path), "review_status": "approved", "rights_status": "owned", "quality": quality.duplicate()})
	var bad = bundle.duplicate(true)
	bad.review_status = "pending"
	check(d.install_bundle(bad).reason == "bundle_not_reviewed", "Manual review required")
	bad = bundle.duplicate(true)
	bad.rig_revision = "other_rig"
	check(d.install_bundle(bad).reason == "identity_mismatch", "Rig identity bound")
	bad = bundle.duplicate(true)
	bad.design_revision = "v0"
	check(d.install_bundle(bad).reason == "identity_mismatch", "Design revision bound")
	bad = bundle.duplicate(true)
	bad.clips[0].quality.hair = false
	check(d.install_bundle(bad).reason == "quality_missing", "Hair quality cannot be skipped")
	bad = bundle.duplicate(true)
	bad.clips[0].rights_status = "unknown"
	check(d.install_bundle(bad).reason == "clip_not_reviewed", "Unknown provenance denied")
	bad = bundle.duplicate(true)
	bad.clips[0].sha256 = "0".repeat(64)
	check(d.install_bundle(bad).reason == "hash_mismatch", "Changed bytes denied")
	bad = bundle.duplicate(true)
	bad.clips[0].resource = "res://src/app.gd"
	check(d.install_bundle(bad).reason == "resource_invalid", "No arbitrary script path")
	bad = bundle.duplicate(true)
	bad.clips[0].resource = fixture_root + "../value.tres"
	check(d.install_bundle(bad).reason == "resource_invalid", "No path traversal")
	bad = bundle.duplicate(true)
	bad.clips[0].resource = method_path
	bad.clips[0].sha256 = FileAccess.get_sha256(method_path)
	check(d.install_bundle(bad).reason == "animation_track_denied", "Animation method calls denied")
	bad = bundle.duplicate(true)
	bad.clips[0].resource = empty_path
	bad.clips[0].sha256 = FileAccess.get_sha256(empty_path)
	check(d.install_bundle(bad).reason == "animation_invalid", "Empty placeholder denied")
	check(d.install_bundle(bundle).ok and d.clips.size() == 7, "Reviewed fixture resources installed")
	check(d.request("idle.relaxed", 0).reason == "renderer_missing", "No false play without renderer")
	var played = []
	var stopped = []
	d.animation_requested.connect(func(layer, id, animation): played.append([layer, id, animation]))
	d.animation_stopped.connect(func(layer, id): stopped.append([layer, id]))
	check(d.request("idle.relaxed", 0).ok, "Body loop dispatched")
	check(d.request("idle.relaxed", 10).reason == "coalesced" and played.size() == 1, "Repeated state coalesces")
	check(d.request("work.progress", 20).ok and stopped.size() == 1, "Higher priority interrupts eligible clip")
	check(d.request("idle.relaxed", 30).reason == "busy", "Low-priority idle cannot interrupt work")
	check(d.request("emotion.smile_warm", 40).ok and d.active.size() == 2, "Face and body run independently")
	check(d.request("interaction.pickup", 50).ok, "Pickup interrupts ordinary work")
	check(d.request("work.success_proud", 60).reason == "busy", "Contact phase protected")
	check(d.tick(950) and d.active.is_empty(), "One-shots finish at deadlines")
	check(d.request("work.success_proud", 1000).ok, "Success dispatches after contact")
	check(d.request("work.success_proud", 1001).reason == "cooldown" and d.active.size() == 1, "Cooldown does not cancel active motion")
	check(d.request("work.progress", 999).reason == "time_invalid", "Backdated clock rejected")
	check(d.request("work.progress", 1001.0).reason == "time_invalid", "Non-integer clock rejected")
	check(not d.tick(-1) and d.active.size() == 1, "Negative tick cannot corrupt state")
	check(d.tick(1900) and d.active.is_empty(), "Success finishes")
	d.set_reduced_motion(true)
	var soft = d.request("locomotion.red_dash", 2000)
	check(soft.ok and soft.event_id == "transition.fade", "Reduced motion resolves reviewed alternative")
	d.set_paused(true)
	check(d.active.is_empty(), "Pause cancels all channels")
	check(d.request("idle.relaxed", 2050).reason == "paused", "No motions while paused")
	d.set_paused(false)
	check(d.request("unknown.event", 2100).reason == "event_unknown", "Unknown semantic event denied")
	bad = bundle.duplicate(true)
	bad.clips.append(bad.clips[0].duplicate(true))
	check(not d.install_bundle(bad).ok and d.clips.size() == 7, "Failed installation is atomic")
	var malformed = catalog.duplicate(true)
	malformed.events.append(malformed.events[0].duplicate(true))
	check(not d.configure(malformed) and d.clips.size() == 7, "Duplicate catalog leaves current bundle intact")
	malformed = catalog.duplicate(true)
	malformed.events[0].reduced_motion_fallback = malformed.events[0].id
	check(not d.configure(malformed), "Fallback cycle rejected")
	malformed = catalog.duplicate(true)
	malformed.events[0].reduced_motion_fallback = "missing"
	check(not d.configure(malformed), "Missing fallback rejected")
	malformed = catalog.duplicate(true)
	malformed.events[0].duration_ms = INF
	check(not d.configure(malformed), "Infinite duration rejected")
	malformed = catalog.duplicate(true)
	malformed.events[0].priority = NAN
	check(not d.configure(malformed), "NaN priority rejected")
	malformed = catalog.duplicate(true)
	malformed.character_id = ""
	check(not d.configure(malformed) and d.clips.size() == 7, "Invalid identity cannot clear installed bundle")
	check(d.summary().renderer_bound, "Renderer presence accurately reported")
	var app = root.get_node("App")
	check(app.motion.summary().installed_clips == 0, "App ships no fake approved motion")
	app.request_motion("work.note_saved")
	check(app.last_motion_result.reason == "asset_missing", "Application bridge reports missing art honestly")
	d.clear()
	d.clips.clear()
	for path in [normal_path, method_path, empty_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_root))
	print("ANIMATION_TESTS: %s checks, %s failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
