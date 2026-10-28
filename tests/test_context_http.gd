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
	for spec in [["timings_success",0],["reasoning_protocol",128],["invalid_budget",9999]]:
		events.clear();provider.submit([{"role":"user","content":spec[0]}],{"max_tokens":32,"context_tokens":512,"reasoning_tokens":spec[1]})
		await wait_event()
		check(events.size()==1 and events[0]==["ok","final only"],"Only final content is emitted, never private trace")
		check(provider.last_usage.get("prompt_ms")==12.5 and provider.last_usage.get("predicted_ms")==21,"Backend prompt/decode timings retained separately")
		check(provider.last_usage.get("total_ms",-1)>=provider.last_usage.get("elapsed_ms",0),"Total includes preflight and generation")
		check(not JSON.stringify(provider.last_usage).contains("PRIVATE"),"Diagnostic fields retain no prompt or reasoning text")
		check(provider.last_usage.get("reasoning_budget")== (128 if spec[1]==128 else 0),"Unrecognized reasoning budget disabled")
	provider.queue_free()
	print("CONTEXT_HTTP_TESTS: %s checks, %s failures" % [checks,failures])
	quit(0 if failures==0 else 1)
