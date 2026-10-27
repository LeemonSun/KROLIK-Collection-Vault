extends SceneTree
const Access=preload("res://src/tools/application_access.gd")
const Intent=preload("res://src/core/desktop_intent.gd")
var checks=0
var failures=0
class FakeAccess extends Access:
	var payloads=[]
	func _request(payload):payloads.append(payload);return true
func _initialize():_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _run():
	var spelling=preload("res://src/core/intent_spelling.gd")
	check(spelling.normalize("аткрой блокнот")=="открой блокнот","One leading typo corrected")
	check(spelling.normalize("откорй Opera GX")=="открой Opera GX","Transposition corrected without changing app name")
	check(spelling.normalize("впиши Search: MiXeD 世界")=="впиши Search: MiXeD 世界","User payload remains exact")
	for phrase in ["закрой окно","удли файл","опиши Поиск: текст","не открой блокнот","close notepad","describe Search: example"]:
		check(spelling.normalize(phrase)==phrase,"Different/negative intent never becomes a write or launch: "+phrase)
	var parser=Intent.new()
	for text in ["нажми Вставка","click Insert","点击 插入"]:
		check(parser.route(text).get("tool")=="access.invoke","Generic named action "+text)
	var entry=parser.route("впиши Поиск: cat & dog <hello>")
	check(entry.get("tool")=="access.write" and entry.args.text=="cat & dog <hello>","Text is typed data, never interpreted")
	check(parser.route("допиши Поиск: текст").args.append,"Explicit append intent")
	var worker=FakeAccess.new();root.add_child(worker)
	check(not worker.act("invoke","Delete"),"No window selected means no action")
	check(worker.payloads.is_empty(),"No invented target")
	worker.adopt({"handle":"123","target_pid":1234,"started":"999","title":"Test window","app":"Test"})
	worker.act("invoke","Insert")
	check(worker.payloads[-1].operation=="inspect","Observe before acting on unknown or stale elements")
	worker._result({"status":"inspected","nodes":[{"id":"1,2","name":"Insert","enabled":true,"invoke":true}]})
	check(worker.payloads[-1].operation=="invoke" and worker.payloads[-1].element_id=="1,2","Actions bind observed runtime ID and window identity")
	worker.nodes=[{"id":"1,2","name":"Same","enabled":true},{"id":"1,3","name":"Same","enabled":true}]
	worker.observed_ms=Time.get_ticks_msec();var before=worker.payloads.size()
	check(not worker.act("invoke","Same") and worker.payloads.size()==before,"Ambiguous elements do not click")
	worker.pending={"operation":"invoke","element_name":"Send"};worker.observed_ms=Time.get_ticks_msec()-31000
	check(not worker.confirm(),"Expired confirmation cannot execute")
	worker.queued_action={"kind":"invoke","name":"Insert","text":"","append":false}
	worker._result({"status":"failed"})
	check(worker.queued_action.is_empty(),"Failed observation cannot replay an old instruction on a later window")
	worker.clear_target()
	check(worker.target.is_empty() and worker.nodes.is_empty() and worker.pending.is_empty(),"Clearing target removes all action authority")
	worker.queue_free()
	print("ACCESS_TESTS: %s checks, %s failures; scoped protocol only, Windows UIA not executed" %[checks,failures])
	quit(0 if failures==0 else 1)
