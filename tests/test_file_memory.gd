extends SceneTree
const Patcher=preload("res://src/tools/text_patch.gd")
const Facts=preload("res://src/core/fact_memory.gd")
var checks=0
var failures=0
func _initialize():_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func save(path,bytes):
	var file=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func _run():
	var folder=ProjectSettings.globalize_path("user://file-memory-test");DirAccess.make_dir_recursive_absolute(folder)
	var path=folder.path_join("settings.ini");var original=PackedByteArray([239,187,191])+"[Video]\r\nFPS=60\r\nLanguage=Русский\r\n".to_utf8_buffer();save(path,original)
	var patch=Patcher.new();patch.backup_directory="user://file-memory-test/backups"
	var plan=patch.prepare(path,"FPS=60","FPS=90")
	check(plan.ok and plan.line==2,"Unique text change gets an exact line preview")
	check(FileAccess.get_file_as_bytes(path)==original,"Preview alone never changes a file")
	check(not patch.commit("guessed").ok,"Invented approval token cannot write")
	var result=patch.commit(plan.token)
	check(result.ok and FileAccess.get_file_as_string(path).contains("FPS=90"),"Approved patch writes and verifies the actual file")
	check(FileAccess.get_file_as_bytes(path).slice(0,3)==PackedByteArray([239,187,191]) and "\r\n" in FileAccess.get_file_as_string(path),"UTF-8 BOM and CRLF preserved")
	check(FileAccess.get_file_as_bytes(patch.last_backup.backup)==original,"Backup preserves exact original bytes")
	check(not patch.commit(plan.token).ok,"Used approval cannot replay")
	plan=patch.prepare_restore();check(plan.ok and patch.commit(plan.token).ok,"Restore goes through the same reviewed transaction")
	check(FileAccess.get_file_as_bytes(path)==original,"Restore returns exact original bytes")
	plan=patch.prepare(path,"FPS=60","FPS=120");save(path,"external change".to_utf8_buffer())
	check(not patch.commit(plan.token).ok and FileAccess.get_file_as_string(path)=="external change","External edit is never overwritten by a stale preview")
	save(path,"same same".to_utf8_buffer());check(not patch.prepare(path,"same","different").ok,"Ambiguous replacements rejected")
	save(path,"x".to_utf8_buffer());plan=patch.prepare(path,"x","y");patch.cancel();check(not patch.commit(plan.token).ok,"Closing a review revokes write authority")
	var json_path=folder.path_join("data.json");save(json_path,'{"value":1}'.to_utf8_buffer())
	check(not patch.prepare(json_path,"1","broken").ok,"Invalid JSON is not written")
	var binary=folder.path_join("data.txt");save(binary,PackedByteArray([0,255,0,1]));check(not patch.prepare(binary,"x","y").ok,"Non-text encodings do not get lossy rewrites")
	var facts=Facts.new();facts.path="user://file-memory-test/facts.json"
	if FileAccess.file_exists(facts.path):DirAccess.remove_absolute(ProjectSettings.globalize_path(facts.path))
	check(facts.load_state() and facts.set_fact("цвет","зелёный"),"Explicit compact fact persisted")
	check(facts.recall("Какой мой любимый цвет?")[0].value=="зелёный","Relevant fact retrieved without full transcript")
	check(facts.set_fact("цвет","синий") and facts.facts.size()==1,"Updating a fact replaces it instead of accumulating transcript")
	var reload=Facts.new();reload.path=facts.path;check(reload.load_state() and reload.facts["цвет"].value=="синий","Facts survive application restart")
	check(facts.set_fact("цвет","",true) and facts.recall("цвет").is_empty(),"Deletion leaves no value in active memory")
	var before={"color":{"value":"green","deleted":false}};var left=before.duplicate(true);var right=before.duplicate(true)
	left["name"]={"value":"Alex","deleted":false};right["color"].value="blue"
	var merged=Facts.merge(before,left,right)
	check(merged.ok and merged.conflicts.is_empty() and merged.facts.has("name") and merged.facts.color.value=="blue","Independent device changes merge without losing facts")
	left.color.value="red";merged=Facts.merge(before,left,right)
	check(merged.conflicts==["color"] and merged.facts.color.value=="red","Divergent cloud edits are surfaced, never silently overwritten")
	check(not Facts.valid({"x":{"value":"v","deleted":false,"command":"shell"}}),"Unknown synced memory fields rejected")
	for i in range(100):facts.set_fact("fact "+str(i),"value "+str(i))
	var file=FileAccess.open(facts.path,FileAccess.READ);check(file.get_length()<10000,"A hundred short facts fit within 10 KB in this fixture");file.close()
	save(facts.path,"{broken".to_utf8_buffer());var corrupt=Facts.new();corrupt.path=facts.path
	check(not corrupt.load_state() and not corrupt.set_fact("x","y") and FileAccess.get_file_as_string(facts.path)=="{broken","Corrupt memory is preserved for recovery")
	var router=preload("res://src/core/router.gd").new()
	for raw in ["запомни факт цвет: Зелёный","remember fact Color: Green","记住事实 颜色：绿色"]:check(router.route(raw).get("tool")=="facts.set","Multilingual explicit fact command")
	check(router.route("редактировать файл").get("tool")=="files.edit_selected","File editing starts from explicit user selection")
	print("FILE_MEMORY_TESTS: %d checks, %d failures; actual files and local merge, no Steam network" %[checks,failures])
	quit(0 if failures==0 else 1)
