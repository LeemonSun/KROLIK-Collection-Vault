extends SceneTree
const Provider=preload("res://src/providers/llama_http_provider.gd")
var provider
var events=[]
var checks=0
var failures=0
func check(ok,text):
	checks+=1
	if not ok:failures+=1;push_error(text)
func _initialize():_run.call_deferred()
func wait_event():
	var deadline=Time.get_ticks_msec()+5000
	while events.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(not events.is_empty(),"Request reaches terminal state")
func _run():
	provider=Provider.new();root.add_child(provider)
	provider.completed.connect(func(text):events.append(["ok",text]))
	provider.failed.connect(func(key):events.append(["error",key]))
	check(provider.configure_local(9931,"a".repeat(64)),"Authenticated owned endpoint")
	var messages=[{"role":"system","content":"system"},{"role":"user","content":"old".repeat(150)},{"role":"assistant","content":"old answer"},{"role":"user","content":"context_success"}]
	check(provider.submit(messages,{"max_tokens":16,"context_tokens":150}),"Context preflight accepted")
	await wait_event()
	check(not events.is_empty() and events[0][0]=="ok","Oversized history trims before generation")
	check(not provider.last_usage.is_empty() and provider.last_truncated,"Usage and length limit exposed")
	events.clear()
	provider.submit([{"role":"system","content":"system"},{"role":"user","content":"overflow".repeat(200)}],{"max_tokens":16,"context_tokens":150})
	await wait_event()
	check(not events.is_empty() and events[0]==["error","model_context_full"],"Current user overflow fails without generation")
	events.clear()
	provider.submit(messages,{"max_tokens":16,"context_tokens":150});provider.cancel()
	await create_timer(0.3).timeout
	check(events.is_empty() and not provider.busy,"Cancel during preflight has no late answer")
	events.clear()
	provider.submit([{"role":"user","content":"dialogue_sampling"}],{"max_tokens":16,"context_tokens":200,"companion_dialogue":true})
	await wait_event()
	check(not events.is_empty() and events[0][0]=="ok","Owned dialogue sampling reaches the HTTP endpoint")
	provider.queue_free()
	print("CONTEXT_HTTP_TESTS: %s checks, %s failures" % [checks,failures])
	quit(0 if failures==0 else 1)
