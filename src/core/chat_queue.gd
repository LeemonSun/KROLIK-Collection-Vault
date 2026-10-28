extends RefCounted
## Ephemeral text only; tools and window context never enter this queue.
const LIMIT=3
var items=[]
var revision=0
func push(text,router):
	if not text is String or text.strip_edges().is_empty() or text.length()>2048:return false
	if items.size()>=LIMIT or router.route(text).get("kind")!="chat":return false
	items.append(text);return true
func take(expected):
	if expected!=revision or items.is_empty():return ""
	return items.pop_front()
func clear():
	items.clear();revision+=1
