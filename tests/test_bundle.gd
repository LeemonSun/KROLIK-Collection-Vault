extends SceneTree
const Bundles=preload("res://src/runtime/bundled_package.gd")
var checks=0
var failures=0
func _initialize():_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _run():
	var missing=Bundles.new();missing.bundle_root="user://no-bundle-here";root.add_child(missing)
	check(missing.finished and missing.packages.is_empty(),"Light package needs no bundle and starts no verification")
	missing.queue_free()
	var path=OS.get_environment("COMPANION_BUNDLE_FIXTURE")
	if not path.is_empty():
		var bundle=Bundles.new();bundle.bundle_root=path;bundle.cache_path="user://test-bundle-cache.json"
		if FileAccess.file_exists(bundle.cache_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(bundle.cache_path))
		root.add_child(bundle)
		check(bundle.packages.size()==3 and bundle.verifier!=null,"All actual pinned AI components detected, verification asynchronous")
		var start=Time.get_ticks_msec()
		while not bundle.finished and Time.get_ticks_msec()-start<120000:await process_frame
		check(bundle.finished,"Bundle verification completes")
		for key in ["text","voice","vision"]:check(bundle.packages.get(key,{}).get("ready",false),"Actual pinned hashes "+key)
		var app=root.get_node("App");var original=app.bundle_catalog
		app.bundle_catalog=bundle;app._bundle_changed()
		check(app.local_runtime.installed() and app.local_runtime.model_path().begins_with(path),"Text uses bundle in place, no AppData copy")
		check(app.speech_input.installed() and app.vision_asset.installed(),"Voice and vision immediately available without installer")
		check(app.local_runtime.pid<0 and app.speech_input.transcriber.asr_pid<0,"Bundle verification does not load AI workers")
		app.bundle_catalog=original
		var cached=Bundles.new();cached.bundle_root=path;cached.cache_path=bundle.cache_path;root.add_child(cached)
		check(cached.finished and cached.verifier==null,"Unchanged bundle reuses receipt and avoids rehashing 2GB")
		var c=JSON.parse_string(FileAccess.get_file_as_string(bundle.cache_path));c["text"]="invalid"
		var file=FileAccess.open(bundle.cache_path,FileAccess.WRITE);file.store_string(JSON.stringify(c));file.close()
		var invalid=Bundles.new();invalid.bundle_root=path;invalid.cache_path=bundle.cache_path;root.add_child(invalid)
		check(not invalid.packages.text.ready and invalid.verifier!=null,"Invalid cached receipt triggers verification instead of trusted startup")
		while not invalid.finished:await process_frame
		cached.queue_free();invalid.queue_free();bundle.queue_free()
	print("BUNDLE_TESTS: %s checks, %s failures; actual_package=%s" %[checks,failures,not path.is_empty()])
	quit(0 if failures==0 else 1)
