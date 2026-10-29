extends SceneTree
var checks=0
var failures=0
func _initialize():_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _run():
	check(ProjectSettings.get_setting("application/config/version")=="0.12.0-desktop-preview","Exported application version")
	check(DirAccess.get_directories_at("res://assets/characters")==PackedStringArray(["leemon_01"]),"Only Leemon resources exist in exported character directory")
	var Queue=load("res://src/core/chat_queue.gd");var Office=load("res://src/tools/office_patch.gd")
	check(Queue!=null and Office!=null,"Real queue and OOXML adapter scripts shipped")
	var app=root.get_node("App")
	check(app.chat_queue.LIMIT==3,"Bounded queue in exported app")
	check(load("res://src/animation/leemon_rig.gd").CLIPS.size()==30,"Same shared-master procedural rig shipped")
	for locale in ["ru","en","zh-Hans"]:
		app.l10n.set_locale(locale)
		check(app.t("office_hint")!="office_hint" and app.t("table_read_cell")!="table_read_cell","Office UI localized "+locale)
	check(load("res://src/tools/office_patch.gd").inventory("invalid".to_utf8_buffer()).is_empty(),"Invalid archive rejected by exported implementation")
	print("PACK_012_TESTS: %d checks, %d failures; exported resource pack on Linux, no Windows execution" %[checks,failures])
	quit(0 if failures==0 else 1)
