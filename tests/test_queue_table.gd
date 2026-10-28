extends SceneTree
const Table=preload("res://src/tools/delimited_table.gd")
const Patch=preload("res://src/tools/text_patch.gd")
var checks=0
var failures=0
class FakeProvider extends Node:
	var inputs=[]
	func submit(messages,_options):inputs.append(messages[-1].content);return true
	func cancel():pass
func _initialize():_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func save(path,bytes):
	var file=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func _run():
	var folder=ProjectSettings.globalize_path("user://queue-table-test");DirAccess.make_dir_recursive_absolute(folder)
	var path=folder.path_join("table.csv")
	var original=PackedByteArray([239,187,191])+'name,value\r\n"Иван, 张",same\r\n"A\nB",same\r\n'.to_utf8_buffer()
	save(path,original)
	var patch=Patch.new();patch.backup_directory="user://queue-table-test/backups"
	var plan=patch.prepare_cell(path,3,2,"same",'new,"quoted"\n中文')
	check(plan.ok and FileAccess.get_file_as_bytes(path)==original,"Coordinate review does not write even when values repeat")
	check(patch.commit(plan.token).ok,"Reviewed CSV transaction writes an actual file")
	var actual=FileAccess.get_file_as_bytes(path)
	check(actual.slice(0,3)==PackedByteArray([239,187,191]),"Table BOM retained")
	var parsed=Table.parse(actual.slice(3).get_string_from_utf8(),",")
	check(parsed.ok and parsed.rows.size()==3 and parsed.rows[2][1].value=='new,"quoted"\n中文',"Quoted commas, escaped quotes, embedded newline and Unicode round-trip")
	check(parsed.rows[1][1].value=="same" and parsed.rows[2][0].value=="A\nB","Identical neighbour and other multiline cell unchanged")
	check(actual.slice(3).get_string_from_utf8().begins_with('name,value\r\n"Иван, 张",same\r\n"A\nB",'),"Untouched bytes and CRLF retained")
	plan=patch.prepare_restore();check(plan.ok and patch.commit(plan.token).ok and FileAccess.get_file_as_bytes(path)==original,"Cell edit has an exact-byte reviewed restore")
	check(not patch.prepare_cell(path,2,2,"wrong","x").ok,"Expected current value must match")
	check(not patch.prepare_cell(path,99,1,"","x").ok,"Out of range coordinate rejected")
	for payload in ["=HYPERLINK(\"url\")"," \t@SUM(A1)","+CMD","-CMD"]:
		check(not patch.prepare_cell(path,2,2,"same",payload).ok,"Formula-like new value rejected")
	plan=patch.prepare_cell(path,2,2,"same","-12.5");check(plan.ok,"Negative numeric data allowed");patch.cancel()
	plan=patch.prepare_cell(path,2,2,"same","changed");save(path,"external edit".to_utf8_buffer())
	check(not patch.commit(plan.token).ok and FileAccess.get_file_as_string(path)=="external edit","External table edit invalidates reviewed transaction")
	for text in ['a,b\n1','"unterminated,b','a"b,c','"a"oops,b','a,b\rc,d']:
		check(not Table.parse(text,",").ok,"Malformed or ragged table rejected")
	check(not Table.parse(",".repeat(256),",").ok,"Column budget enforced")
	check(not Table.parse("a\n".repeat(10001),",").ok,"Row budget enforced")
	check(not Table.parse("x".repeat(1048577),",").ok,"Byte budget enforced")
	path=folder.path_join("table.tsv");save(path,"name\tvalue\n甲\t乙\n".to_utf8_buffer())
	plan=patch.prepare_cell(path,2,2,"乙","\t中文");check(plan.ok and patch.commit(plan.token).ok,"TSV quoted tab transaction")
	check(Table.parse(FileAccess.get_file_as_string(path),"\t").rows[1][1].value=="\t中文","TSV literal tab round-trip")
	var app=root.get_node("App");app.cancel();app.application_access.target={}
	var queue=preload("res://src/core/chat_queue.gd").new()
	for command in ["/timer 10","открой блокнот","редактировать файл"]:check(not queue.push(command,app.router),"Tool rejected even with an empty queue")
	check(not queue.push("x".repeat(2049),app.router) and not queue.push("  ",app.router),"Input budgets enforced before retention")
	var old=app.provider;var fake=FakeProvider.new();app.add_child(fake);app.provider=fake;app.local_ai_enabled=false
	app.submit("Объясни радугу")
	check(fake.inputs.size()==1 and app.queue_chat("Explain gravity") and app.queue_chat("解释彩虹") and app.queue_chat("Расскажи о Луне"),"One inference active and three text requests queued")
	check(not app.queue_chat("fourth") and fake.inputs.size()==1,"Queue is bounded and never starts parallel inference")
	for command in ["/timer 10","открой блокнот","редактировать файл"]:check(not app.queue_chat(command),"Tool commands cannot be deferred")
	app._on_answer("Радуга возникает при преломлении и отражении света в каплях воды.")
	await process_frame;await process_frame
	check(fake.inputs.size()==2 and fake.inputs[1]=="Explain gravity" and app.chat_queue.items.size()==2,"Successful completion drains exactly the next FIFO request")
	app._on_failure("model_invalid_response");await process_frame
	check(app.chat_queue.items.is_empty() and fake.inputs.size()==2,"Failure stops the remaining queue")
	app.submit("Объясни радугу");app.queue_chat("Explain gravity")
	var revision=app.chat_queue.revision;app.cancel();app._drain_queued_chat(revision)
	check(app.chat_queue.items.is_empty() and fake.inputs.size()==3 and app.state.current=="idle","Stop revokes even a previously scheduled drain")
	app.submit("Объясни радугу");app.queue_chat("Explain gravity");app.set_paused(true);await process_frame
	check(app.chat_queue.items.is_empty() and app.state.current=="idle","Pause cancels active and queued work")
	app.set_paused(false);app.submit("Объясни радугу");app.application_access.target={"title":"new target"}
	check(not app.queue_chat("Explain gravity"),"Selected window context is excluded from deferred work")
	app.cancel();app.application_access.target={};app.provider=old;fake.queue_free()
	print("QUEUE_TABLE_TESTS: %d checks, %d failures; fake inference scheduling and real UTF-8 file transactions" %[checks,failures])
	quit(0 if failures==0 else 1)
