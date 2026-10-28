extends RefCounted
const MAX_BYTES = 262144
var path = "user://conversation-v1.json"
var writable = true
var messages = []
var turns = []
var truncated=false
func load_history():
	if not FileAccess.file_exists(path): return true
	var file = FileAccess.open(path, FileAccess.READ)
	if not file or file.get_length()>MAX_BYTES: writable=false; return false
	var parser = JSON.new()
	if parser.parse(file.get_as_text())!=OK: writable=false; return false
	var value = parser.data
	if not value is Dictionary or value.get("schema_version")!=1 or not value.get("messages") is Array or value.messages.size()>100:
		writable=false; return false
	if value.has("truncated") and not value.truncated is bool:writable=false;return false
	for message in value.messages:
		if not message is Dictionary or message.get("speaker") not in ["user","assistant"] or not message.get("text") is String or message.text.length()>16384:
			writable=false; return false
	messages=value.messages
	truncated=bool(value.get("truncated",false))
	turns=[]
	var pending=""
	for message in messages:
		if message.speaker=="user": pending=message.text
		elif not pending.is_empty():
			turns.append({"role":"user","content":pending})
			turns.append({"role":"assistant","content":message.text})
			pending=""
	while turns.size()>16: turns.pop_front()
	return true
func save_history(source):
	if not writable: return false
	var recent=source.filter(func(message):return not message.get("ephemeral",false)).duplicate(true)
	while recent.size()>100:recent.pop_front();truncated=true
	var text=JSON.stringify({"schema_version":1,"messages":recent,"truncated":truncated})
	while text.to_utf8_buffer().size()>MAX_BYTES and not recent.is_empty():
		recent.pop_front()
		truncated=true
		text=JSON.stringify({"schema_version":1,"messages":recent,"truncated":truncated})
	var file=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if not file:return false
	file.store_string(text); file.flush(); file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))==OK
func erase():
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(path))!=OK: return false
	if FileAccess.file_exists(path+".tmp"):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".tmp"))
	messages=[]; turns=[]; writable=true;truncated=false
	return true
func retrieve(query, notes):
	var rx=RegEx.new(); rx.compile("[\\p{L}\\p{N}]{3,}")
	var words=[]
	for match_ in rx.search_all(query.to_lower()):
		var word=match_.get_string()
		if word not in ["what","does","that","have","your","with","which","меня","какой","какая","какие","помнишь","remember"]: words.append(word)
	# Chinese queries often have no spaces; short overlapping tokens bridge phrasing.
	for i in range(query.length()-1):
		if query.unicode_at(i)>=0x4e00 and query.unicode_at(i)<=0x9fff: words.append(query.substr(i,2))
	var scored=[]
	for note in notes:
		var score=0
		var candidate=str(note.text).to_lower()
		for word in words:
			if word in candidate: score+=1
		if score>0:scored.append({"score":score,"text":note.text})
	scored.sort_custom(func(a,b):return a.score>b.score)
	return scored.slice(0,mini(3,scored.size()))
