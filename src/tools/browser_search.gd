extends RefCounted
## Explicit user search only. A fixed HTTPS endpoint; no model-provided URL or shell command.
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
	# Injected opener is a test seam; the app uses only the OS default browser.
	var code = opener.call(result.url) if opener.is_valid() else OS.shell_open(result.url)
	return {"ok": code == OK, "status": "requested" if code == OK else "open_failed", "url": result.url}
