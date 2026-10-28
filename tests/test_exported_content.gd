extends SceneTree
var failures=0
var checks=0
func _initialize():_run.call_deferred()
func check(ok,text):
	checks+=1
	if not ok:failures+=1;push_error(text)
func _run():
	check(ProjectSettings.get_setting("application/config/version")=="0.12.0-desktop-preview","Correct product version inside PCK")
	check(ProjectSettings.get_setting("application/config/name")=="Companion Foundation","Existing AppData model/profile identity retained")
	check(FileAccess.get_sha256("res://native/desktop_bridge.ps1")==OS.get_environment("COMPANION_HELPER_SHA"),"Exact reviewed Windows helper exported")
	check(FileAccess.get_sha256("res://native/accessibility_bridge.ps1")==OS.get_environment("COMPANION_ACCESS_HELPER_SHA"),"Exact scoped UIA/selected-state helper exported")
	var migration=JSON.parse_string(FileAccess.get_file_as_string("res://native/legacy_patch_files.json"))
	check(migration is Dictionary and migration.get("entries",[]).size()==12,"Exact migration inventory exported")
	check(ResourceLoader.exists("res://assets/characters/leemon_01/master_v1.png") and load("res://assets/characters/leemon_01/master_v1.png").get_size()==Vector2(1199,1312),"Leemon asset exported")
	check(preload("res://src/animation/leemon_rig.gd").CLIPS.size()==26,"All26procedural states shipped")
	check(preload("res://src/core/fact_memory.gd").MAX_FACTS==1024,"Compact fact storage shipped")
	check("ini" in preload("res://src/tools/text_patch.gd").EXTENSIONS,"Selected text/config review shipped")
	var clock=preload("res://src/tools/world_clock.gd").new()
	check(clock.resolve("Beijing").ok,"Offline world clock data exported")
	var app=root.get_node("App")
	var events=[]
	app.desktop_actions.completed.connect(func(result):events.append(result))
	app.desktop_actions.test_runner=true
	app.desktop_actions.runner=OS.get_environment("COMPANION_PWSH")
	check(app.desktop_actions.request_metrics([]),"Godot starts the actual helper with typed data")
	var deadline=Time.get_ticks_msec()+10000
	while events.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(not events.is_empty() and events[0].get("status")=="ok" and events[0].get("operation")=="metrics","Actual helper result returns through nonce protocol")
	var helper=FileAccess.get_file_as_bytes("user://support/desktop_bridge.ps1")
	check(helper.slice(0,3)==PackedByteArray([239,187,191]),"UTF-8 BOM supports Windows PowerShell 5.1 Cyrillic/CJK")
	check(DirAccess.get_files_at("user://support/jobs").is_empty(),"No request/result litter after job completion")
	var access=app.application_access
	access.test_runner=true;access.runner=OS.get_environment("COMPANION_PWSH")
	access.adopt({"handle":"123","target_pid":234,"started":"345","title":"Test","app":"Test"})
	var replies=[];access.completed.connect(func(reply):replies.append(reply))
	check(access.read_content(),"Exported read operation reaches actual helper")
	deadline=Time.get_ticks_msec()+10000
	while replies.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(not replies.is_empty() and replies[0].get("operation")=="read" and replies[0].get("status")=="unsupported","Non-Windows helper refuses to simulate a read")
	check(DirAccess.get_files_at("user://support/accessibility/jobs").is_empty(),"Read request IPC cleaned after actual helper completion")
	print("EXPORTED_CONTENT_TESTS: %s checks, %s failures; actual helper round trip; Windows COM not exercised" % [checks,failures])
	quit(0 if failures==0 else 1)
