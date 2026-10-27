extends SceneTree
const Search = preload("res://src/tools/browser_search.gd")
const Router = preload("res://src/core/router.gd")
var checks = 0
var failures = 0
var opened = []
func _initialize():
	_run.call_deferred()
func check(ok, label):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _open(url):
	opened.append(url)
	return OK
func _fail(_url):
	return ERR_CANT_OPEN
func _run():
	var search = Search.new()
	for query in ["погода Москва", "桌面助手", "anime character design", "https://example.org/?a=1&b=2", "javascript:alert(1)"]:
		var result = search.prepare(query)
		check(result.ok and result.url.begins_with(Search.ENDPOINT) and result.url.substr(Search.ENDPOINT.length()).uri_decode() == query, "Query is encoded as data: " + query)
	for bad in ["", "   ", "x".repeat(513), "a\nb", "a\tb", "a" + String.chr(127) + "b", 12, null]:
		check(not search.open_query(bad, _open).ok, "Invalid input rejected")
	check(opened.is_empty(), "No side effect for invalid input")
	check(search.open_query("a & b", _open).status == "requested" and opened.size() == 1, "Explicit handoff only once")
	check(search.open_query("query", _fail).status == "open_failed", "OS failure is reported")
	check(search.set_browser("opera"),"Opera preference")
	check(not search.set_browser("arbitrary.exe") and search.browser_id=="opera","Unknown executable choice denied")
	var candidates=search.opera_candidates("opera_gx",{"LOCALAPPDATA":"C:/Users/test/AppData/Local","PROGRAMFILES":"C:/Program Files"})
	check(candidates.size()==2 and candidates[0].ends_with("Programs/Opera GX/launcher.exe"),"Known Opera GX locations")
	check(search.opera_candidates("unknown",{}).is_empty(),"Unknown path recipe denied")
	search.set_browser("system")
	var router = Router.new()
	for command in ["/search abc", "/поиск привет", "/搜索 你好"]:
		check(router.route(command).tool == "browser.search", "Multilingual search")
	check(router.route("/search").kind == "invalid", "Missing query")
	check(router.route("search for something").kind == "chat", "Natural language does not cause an automatic browser action")
	print("SEARCH_TESTS: %s checks, %s failures; OS opener replaced by test callable" % [checks, failures])
	quit(0 if failures == 0 else 1)
