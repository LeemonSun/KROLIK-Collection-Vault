extends "res://src/providers/provider_base.gd"
## Local HTTP adapter for an owned worker or the explicit developer endpoint.
## Only a literal loopback endpoint is permitted; redirects and proxies are disabled.
const ENDPOINT = "http://127.0.0.1:9931/v1/chat/completions"
var endpoint = ENDPOINT
var auth_token = ""
var http
var transport_revision=0
var phase=""
var request_messages=[]
var request_options={}
var last_usage={}
var last_truncated=false
var generation_started_ms=0
var request_started_ms=0
var preflight_tokens=0
var template_ms=0
var tokenize_ms=0
var stage_started_ms=0

func _ready():
	_make_http()
func _make_http():
	http = HTTPRequest.new()
	http.timeout = 30.0
	http.body_size_limit = 1024 * 1024
	http.max_redirects = 0
	http.set_http_proxy("", -1)
	http.set_https_proxy("", -1)
	add_child(http)
	var expected=transport_revision
	http.request_completed.connect(func(result,code,headers,body):
		if expected==transport_revision:_on_completed(result,code,headers,body))

func submit(messages, options = {}):
	if busy:
		return false
	request_messages=messages.duplicate(true)
	request_options=options.duplicate(true)
	last_usage={}
	request_started_ms=Time.get_ticks_msec();preflight_tokens=0;template_ms=0;tokenize_ms=0
	last_truncated=false
	busy=true
	if options.has("response_schema") and auth_token.is_empty():
		busy=false;request_messages=[];request_options={};_fail("goal_local_only");return false
	if options.get("multimodal",false):
		if auth_token.is_empty() or messages.size()!=2 or JSON.stringify(messages).length()>600000:
			busy=false;_fail("vision_failed");return false
		return _generate()
	if not auth_token.is_empty():
		return _apply_template()
	return _generate()

func _post(path,payload):
	var headers=PackedStringArray(["Content-Type: application/json"])
	if not auth_token.is_empty():headers.append("Authorization: Bearer "+auth_token)
	var base=endpoint.trim_suffix("/v1/chat/completions")
	var error=http.request(base+path,headers,HTTPClient.METHOD_POST,JSON.stringify(payload))
	if error!=OK:
		busy=false
		request_messages=[];request_options={}
		_fail("model_connection_failed")
		return false
	return true

func reasoning_tokens():
	if auth_token.is_empty() or request_options.has("response_schema") or request_options.get("multimodal",false):return 0
	return 128 if request_options.get("reasoning_tokens",0)==128 else 0

func total_output_tokens():
	return clampi(int(request_options.get("max_tokens",128)),16,512-reasoning_tokens())+reasoning_tokens()

func _apply_template():
	phase="template";stage_started_ms=Time.get_ticks_msec()
	return _post("/apply-template",{"messages":request_messages,"add_generation_prompt":true,"chat_template_kwargs":{"enable_thinking":reasoning_tokens()>0}})

func _generate():
	phase="generate"
	generation_started_ms=Time.get_ticks_msec()
	var body = {
		"model": "companion",
		"messages": request_messages,
		"stream": false,
		"max_tokens": total_output_tokens(),
		"temperature": 0.4,
		"top_p": 0.9,
		"top_k": 40,
		"min_p": 0.0,
		"chat_template_kwargs": {"enable_thinking": reasoning_tokens()>0}
	}
	if reasoning_tokens()>0:
		body["reasoning_budget_tokens"]=reasoning_tokens()
		body["reasoning_format"]="deepseek"
	if request_options.get("companion_dialogue",false) and not auth_token.is_empty():
		body["temperature"]=0.55;body["top_p"]=0.85;body["top_k"]=20
		body["presence_penalty"]=0.25;body["repeat_penalty"]=1.0
	if request_options.get("response_schema") is Dictionary:
		body["response_format"]={"type":"json_object"}
		body["json_schema"]=request_options.response_schema
	return _post("/v1/chat/completions",body)

func cancel():
	transport_revision+=1
	if http:
		http.cancel_request()
	busy = false
	phase=""
	request_messages=[]
	request_options={}
	if is_inside_tree() and http is HTTPRequest:
		http.queue_free();http=null;_make_http()

func _on_completed(result, code, _headers, body):
	if not busy:
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		busy=false
		request_messages=[];request_options={}
		_fail("model_connection_failed")
		return
	var parser = JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK:
		busy=false
		_fail("model_invalid_response")
		return
	var parsed = parser.data
	if not (parsed is Dictionary):
		busy=false
		_fail("model_invalid_response")
		return
	if phase=="template":
		template_ms+=Time.get_ticks_msec()-stage_started_ms
		if not parsed.get("prompt") is String:
			busy=false;_fail("model_invalid_response");return
		phase="tokenize";stage_started_ms=Time.get_ticks_msec()
		_post("/tokenize",{"content":parsed.prompt,"add_special":false,"parse_special":true})
		return
	if phase=="tokenize":
		tokenize_ms+=Time.get_ticks_msec()-stage_started_ms
		if not parsed.get("tokens") is Array:
			busy=false;_fail("model_invalid_response");return
		preflight_tokens=parsed.tokens.size()
		var needed=parsed.tokens.size()+total_output_tokens()+64
		if needed>int(request_options.get("context_tokens",2048)):
			if request_messages.size()>2:
				request_messages.remove_at(1);request_messages.remove_at(1)
				_apply_template()
			else:busy=false;_fail("model_context_full")
		else:_generate()
		return
	busy=false
	var choices = parsed.get("choices", [])
	if not (choices is Array) or choices.is_empty() or not (choices[0] is Dictionary):
		_fail("model_invalid_response")
		return
	var message = choices[0].get("message", {})
	if not (message is Dictionary) or not (message.get("content") is String):
		_fail("model_invalid_response")
		return
	var content = message.content.strip_edges()
	if content.is_empty() or content.length() > 16384:
		_fail("model_invalid_response")
		return
	# Model replies cannot bypass the separate proposal/approval executor.
	last_truncated=choices[0].get("finish_reason")=="length"
	var usage=parsed.get("usage",{})
	last_usage=usage if usage is Dictionary else {}
	last_usage["elapsed_ms"]=Time.get_ticks_msec()-generation_started_ms
	last_usage["total_ms"]=Time.get_ticks_msec()-request_started_ms
	last_usage["template_ms"]=template_ms;last_usage["tokenize_ms"]=tokenize_ms
	last_usage["preflight_tokens"]=preflight_tokens
	last_usage["reasoning_budget"]=reasoning_tokens()
	var timings=parsed.get("timings",{})
	if timings is Dictionary:
		for key in ["prompt_n","prompt_ms","predicted_n","predicted_ms","cache_n"]:
			var value=timings.get(key)
			if (value is int or value is float) and is_finite(float(value)) and value>=0:last_usage[key]=value
	request_messages=[]
	request_options={}
	completed.emit(content)

func capabilities():
	return {"available": true, "network": "loopback_only", "streaming": false, "tools": false}


func configure_local(port, token):
	if not port is int or port < 1024 or port > 65535 or not token is String or token.length() != 64 or not token.is_valid_hex_number(false):
		return false
	cancel()
	endpoint = "http://127.0.0.1:%s/v1/chat/completions" % port
	auth_token = token
	return true

func _fail(key):
	busy=false;phase="";request_messages=[];request_options={}
	failed.emit(key)
