extends RefCounted
## Conservative UTF-8 byte bound; preserves complete recent dialogue pairs.
func build(system_text, user_text, history, options):
	if options.get("server_token_budget",false):
		var candidates=[{"role":"system","content":system_text}]
		candidates.append_array(history.slice(maxi(0,history.size()-16)))
		candidates.append({"role":"user","content":user_text})
		return {"ok":true,"messages":candidates}
	var limit = int(options.get("context_tokens", 2048)) - int(options.get("max_tokens", 128)) - 256
	var used = system_text.to_utf8_buffer().size() + user_text.to_utf8_buffer().size()
	if used > limit:
		return {"ok": false, "messages": []}
	var retained = []
	var index = history.size()-2
	while index >= 0:
		var pair_size = str(history[index].content).to_utf8_buffer().size() + str(history[index+1].content).to_utf8_buffer().size() + 32
		if used + pair_size > limit:
			break
		retained.push_front(history[index+1])
		retained.push_front(history[index])
		used += pair_size
		index -= 2
	var messages = [{"role":"system", "content":system_text}]
	messages.append_array(retained)
	messages.append({"role":"user", "content":user_text})
	return {"ok":true, "messages":messages}
