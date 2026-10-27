extends RefCounted
## Explicit user search only. A fixed HTTPS endpoint; no model-provided URL or shell command.
var browser_id = "system"
const ENDPOINT = "https://duckduckgo.com/?q="

func prepare(query):
	if typeof(query) != TYPE_STRING:
		return {"ok": false, "status": "invalid_query"}
	var text = query.strip_edges()
	if text.is_empty() or text.length() > 512:
		return {"ok": false, "status": "invalid_query"}
	for i in range(query.length()):
		if query.unicode_at(i) < 32 or query.unicode_at(i) == 127:
			return {"ok": false, "status": "invalid_query"}
	return {"ok": true, "status": "prepared", "url": ENDPOINT + text.uri_encode()}

func open_query(query, opener = Callable()):
	var result = prepare(query)
	if not result.ok:
		return result
	return open_url(result.url,opener)

func open_url(url,opener=Callable()):
	if not url is String or url.length()>2048 or not (url.begins_with("https://") or url.begins_with("http://")):
		return {"ok":false,"status":"invalid_url"}
	for i in range(url.length()):
		if url.unicode_at(i)<33 or url.unicode_at(i)==127:return {"ok":false,"status":"invalid_url"}
	if url.split("://",false,1)[1].is_empty():return {"ok":false,"status":"invalid_url"}
	# Injected opener is a test seam; the app uses only the OS default browser.
	var code = FAILED
	if opener.is_valid():
		code = opener.call(url)
	elif browser_id == "system":
		code = OS.shell_open(url)
	else:
		var path = find_opera(browser_id)
		if path.is_empty():
			return {"ok":false,"status":"browser_missing","url":url}
		code = OK if OS.create_process(path,[url],false)>0 else ERR_CANT_OPEN
	return {"ok": code == OK, "status": "requested" if code == OK else "open_failed", "url": url}

func set_browser(id):
	if id not in ["system","opera","opera_gx"]:
		return false
	browser_id=id
	return true

func opera_candidates(id, roots):
	if id not in ["opera","opera_gx"]:
		return []
	var folder="Opera GX" if id=="opera_gx" else "Opera"
	var values=[]
	for key in ["LOCALAPPDATA","PROGRAMFILES","PROGRAMFILES(X86)"]:
		var base=str(roots.get(key,""))
		if base.is_empty():
			continue
		values.append(base.path_join("Programs").path_join(folder).path_join("launcher.exe") if key=="LOCALAPPDATA" else base.path_join(folder).path_join("launcher.exe"))
	return values

func find_opera(id):
	if OS.get_name()!="Windows":
		return ""
	var roots={}
	for key in ["LOCALAPPDATA","PROGRAMFILES","PROGRAMFILES(X86)"]:
		roots[key]=OS.get_environment(key)
	for path in opera_candidates(id,roots):
		if FileAccess.file_exists(path):
			return path
	return ""
