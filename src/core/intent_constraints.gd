extends RefCounted
## Conservative scope: leading/unknown negation blocks; a trailing no-close condition is retained and enforced.
static func analyze(raw):
	var text=str(raw).strip_edges();var lowered=text.to_lower()
	var literal=RegEx.new();literal.compile("^(?:впиши|допиши|write|append|输入|追加)\\s+[^:：]+[:：]")
	var writing=literal.search(lowered)
	var checked=lowered.left(writing.get_end()) if writing else lowered
	var negative=RegEx.new();negative.compile("(?:^|[\\s,;.!?，；。])(?:не\\s+|do\\s+not\\s+|don['’]?t\\s+)|(?:不要|别)(?=关闭|打开|点击|连接|删除|输入|切换|选择|发送|退出)")
	var hit=negative.search(checked)
	if not hit:return {"blocked":false,"primary":text,"no_close":false}
	var prefix=checked.left(hit.get_start()).strip_edges().trim_suffix(",").trim_suffix(";").strip_edges()
	var tail=checked.substr(hit.get_start()).strip_edges().trim_prefix(",").trim_prefix(";").strip_edges()
	var close=RegEx.new();close.compile("^(?:не\\s+(?:закрывай|закрывать|закрыть)\\s+(?:это\\s+|текущее\\s+)?(?:окно|приложение)|(?:do\\s+not|don['’]?t)\\s+close\\s+(?:(?:the|this)\\s+)?(?:window|app|application))[.!?]*$")
	var positive=RegEx.new();positive.compile("(?:^|\\s)(?:открой|запусти|включи|подключи|найди|выбери|раскрой|нажми|впиши|введи|отключи|open|launch|enable|connect|find|select|expand|click|write|disable)(?:\\s|$)")
	if not prefix.is_empty() and close.search(tail) and positive.search(prefix):
		var primary=text.left(hit.get_start()).strip_edges().trim_suffix(",").trim_suffix(";").strip_edges()
		var joiner=RegEx.new();joiner.compile("(?i)\\s+(?:и|and)$")
		return {"blocked":false,"primary":joiner.sub(primary,""),"no_close":true}
	return {"blocked":true,"primary":text,"no_close":false}
static func permits_control(name,goal):
	var condition=analyze(goal)
	if condition.blocked:return false
	if not condition.no_close:return true
	var label=str(name).to_lower().strip_edges()
	if label in ["x","×","✕","✖"]:return false
	for word in ["close","exit","quit","закры","выход","выйти","关闭","退出"]:
		if word in label:return false
	return true
