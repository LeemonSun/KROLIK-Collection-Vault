extends RefCounted
## A short user-authored sequence. No model-generated steps or persisted authority.
const MAX_STEPS=4
var steps=[]
var index=0
var target={}
var active=false
var revision=0
static func parse(raw):
	if not raw is String or raw.strip_edges().is_empty() or raw.length()>800:return {"ok":false}
	var items=[];var chunk="";var quote="";var i=0
	while i<raw.length():
		var ch=raw[i]
		if not quote.is_empty():
			chunk+=ch
			if ch==quote:quote=""
			i+=1;continue
		if ch in ['"','«','“']:
			quote={'"':'"','«':'»','“':'”'}[ch];chunk+=ch;i+=1;continue
		var width=1 if ch=="\n" else (3 if raw.substr(i,3)==" → " else (4 if raw.substr(i,4)==" -> " else 0))
		if width>0:
			items.append(chunk);chunk="";i+=width
		else:chunk+=ch;i+=1
	items.append(chunk)
	if not quote.is_empty() or items.size()>MAX_STEPS:return {"ok":false}
	var clean=[];var numbering=RegEx.new();numbering.compile("^\\s*(?:[1-4][.)]|[-•])\\s+")
	for item in items:
		var step=numbering.sub(item,"",false).strip_edges()
		if step.is_empty() or step.length()>800 or preload("res://src/core/action_proposal.gd").negative_intent(step):return {"ok":false}
		clean.append(step)
	return {"ok":true,"steps":clean}
func begin(items,identity):
	clear();steps=items.duplicate();target=identity.duplicate(true);active=steps.size()>1
func current():return steps[index] if index<steps.size() else ""
func advance(verified):
	if not active:return "single"
	if not verified:clear();return "unverified"
	index+=1
	if index>=steps.size():clear();return "complete"
	return "next"
func clear():
	revision+=1;steps=[];index=0;target={};active=false
