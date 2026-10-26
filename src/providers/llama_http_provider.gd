extends "res://src/providers/provider_base.gd"
## Optional developer adapter. An embedded managed worker is NOT yet included.
## Only a literal loopback endpoint is permitted; redirects and proxies are disabled.
const ENDPOINT = "http://127.0.0.1:9931/v1/chat/completions"
var http

func _ready():
	http = HTTPRequest.new()
	http.timeout = 60.0
	http.body_size_limit = 1024 * 1024
	http.max_redirects = 0
	http.set_http_proxy("", -1)
	http.set_https_proxy("", -1)
	add_child(http)
	http.request_completed.connect(_on_completed)

func submit(messages, options = {}):
	if busy:
		return false
	var body = {
		"model": "companion",
		"messages": messages,
		"stream": false,
		"max_tokens": clampi(int(options.get("max_tokens", 128)), 16, 512),
		"temperature": 0.6
	}
	busy = true
	var error = http.request(ENDPOINT, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		busy = false
		failed.emit("model_connection_failed")
		return false
	return true

func cancel():
	if http:
		http.cancel_request()
	busy = false

func _on_completed(result, code, _headers, body):
	if not busy:
		return
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit("model_connection_failed")
		return
	var parser = JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK:
		failed.emit("model_invalid_response")
		return
	var parsed = parser.data
	if not (parsed is Dictionary):
		failed.emit("model_invalid_response")
		return
	var choices = parsed.get("choices", [])
	if not (choices is Array) or choices.is_empty() or not (choices[0] is Dictionary):
		failed.emit("model_invalid_response")
		return
	var message = choices[0].get("message", {})
	if not (message is Dictionary) or not (message.get("content") is String):
		failed.emit("model_invalid_response")
		return
	var content = message.content.strip_edges()
	if content.is_empty() or content.length() > 16384:
		failed.emit("model_invalid_response")
		return
	# tool_calls are deliberately ignored; no model-driven effects in v0.1.
	completed.emit(content)

func capabilities():
	return {"available": true, "network": "loopback_only", "streaming": false, "tools": false}

