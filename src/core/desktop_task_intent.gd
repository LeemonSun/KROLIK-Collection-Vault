extends RefCounted
## Narrow command boundary; free-form goals still use the shared agent.
func route(text):
	var vpn=RegEx.new();vpn.compile("(?i)^(?:включи|подключи|connect|enable)\\s+(?:vpn|впн)(?:\\s+(.{1,128}))?$")
	var v=vpn.search(text.strip_edges())
	if v:return {"kind":"tool","tool":"desktop.task","args":{"action":"vpn","name":v.get_string(1)}}
	if text.strip_edges() in ["连接VPN","开启VPN"]:return {"kind":"tool","tool":"desktop.task","args":{"action":"vpn","name":""}}
	var chain=RegEx.new();chain.compile("(?i)^(?:открой|запусти|open|launch)\\s+(.{1,80}?)\\s+(?:и|and)\\s+(?:включи|подключи|connect|enable)\\s+(?:vpn|впн)(?:\\s+(.{1,128}))?$")
	var c=chain.search(text.strip_edges())
	if c:return {"kind":"tool","tool":"desktop.task","args":{"action":"launch_vpn","target":c.get_string(1),"name":c.get_string(2)}}
	var chinese=RegEx.new();chinese.compile("^启动(.{1,80}?)并连接VPN$")
	var cn=chinese.search(text.strip_edges())
	if cn:return {"kind":"tool","tool":"desktop.task","args":{"action":"launch_vpn","target":cn.get_string(1),"name":""}}
	var patterns=[
		["^(?:открой\\s+браузер\\s+и\\s+)?(?:найди|покажи|открой)\\s+(?:мне\\s+)?(?:там\\s+)?(?:во?\\s+вкладках\\s+)(.+)$","tabs"],
		["^(?:find|show|open)\\s+(?:the\\s+)?(?:browser\\s+)?tab\\s+(.+)$","tabs"],
		["^(?:启动)(.{1,80}?)并(点击.+)$","launch_goal"],
		["^(?:查找|打开|切换到)标签页\\s*(.+)$","tabs"],
		["^(?:открой|запусти)\\s+(.{1,80}?)\\s+и\\s+(нажми\\s+.+)$","launch_goal"],
		["^(?:open|launch)\\s+(.{1,80}?)\\s+and\\s+(click\\s+.+)$","launch_goal"]]
	for pair in patterns:
		var re=RegEx.new();re.compile("(?i)"+pair[0])
		var m=re.search(text.strip_edges())
		if m:
			if pair[1]=="tabs":
				var query=m.get_string(1).strip_edges().trim_suffix(".")
				if query.length()<2 or query.length()>100:return {}
				return {"kind":"tool","tool":"desktop.task","args":{"action":"tabs","query":query}}
			return {"kind":"tool","tool":"desktop.task","args":{"action":"launch_goal","target":m.get_string(1),"goal":m.get_string(2)}}
	return {}
static func tab_key(value):
	var key=str(value).to_lower().strip_edges()
	for word in ["саундклауд","саунклауд","саунд клауд","саунклауд"]:key=key.replace(word,"soundcloud")
	return key
