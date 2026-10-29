extends RefCounted
## Explicit desktop delegation. Ordinary conversation never triggers discovery.
func route(raw):
	var text=raw.strip_edges()
	if preload("res://src/core/action_proposal.gd").negative_intent(text):return {}
	var patterns=[
		["^(?:включи|подключи)\\s+(?:мой\\s+)?(?:vpn|впн)\\s+(.{2,100})$","capture","task"],
		["^(?:connect|enable)\\s+(?:my\\s+)?vpn\\s+(.{2,100})$","capture","task"],
		["^(?:连接|开启)VPN\\s+(.{1,100})$","capture","task"],
		["^(?:найди\\s+и\\s+)?(?:включи|подключи)\\s+(?:мой\\s+)?(?:впн|vpn)$","","task"],
		["^(?:connect|enable)\\s+(?:my\\s+)?vpn$","","task"],
		["^(?:连接|开启)(?:我的)?VPN$","","task"],
		["^(?:открой|запусти)\\s+(.{2,100}?)\\s+и\\s+(.+)$","capture","task"],
		["^(?:open|launch)\\s+(.{2,100}?)\\s+and\\s+(.+)$","capture","task"],
		["^(?:打开|启动)(.{1,100}?)并(.+)$","capture","task"],
		["^(?:в|через)\\s+(.{2,100}?)\\s+(включи|выключи|настрой|поменяй|найди|напиши|впиши)(.+)$","capture","whole"],
		["^在(.{1,100}?)(?:中|里)(.+)$","capture","whole"],
		["^in\\s+(.{2,100}?)\\s+(enable|disable|configure|set|find|write)(.+)$","capture","whole"]]
	for pair in patterns:
		var re=RegEx.new();re.compile("(?i)"+pair[0]);var m=re.search(text)
		if not m:continue
		var query=m.get_string(1).strip_edges() if pair[1]=="capture" else ""
		return {"kind":"tool","tool":"agent.discover","args":{"query":query,"goal":text,"open_only":false}}
	return {}
