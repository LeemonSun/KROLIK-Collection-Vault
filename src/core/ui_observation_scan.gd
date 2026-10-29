extends RefCounted
## Read-only pagination over ONE bounded snapshot. Effects still require ordinary review/preflight.
var coverage={}
var pages=[]
var index=0
var winners=[]
var active=false
var calls=0
const MAX_CALLS=12
func begin(context):
	clear()
	coverage=context.get("coverage",{}).duplicate(true)
	pages=context.get("pages",[context]).duplicate(true)
	# Preserve the existing separate draft-composition contract. Its omitted count remains explicit.
	if context.get("draft_allowed",false):pages=pages.slice(0,1)
	active=pages.size()>1;calls=1
func current():return pages[index] if index<pages.size() else {}
func accept(plan):
	if not active:return "single"
	if plan.action=="ask":return "ask"
	if plan.action!="none":winners.append({"plan":plan.duplicate(true),"context":current().duplicate(true)})
	index+=1
	if index<pages.size():
		if calls>=MAX_CALLS:active=false;return "budget"
		calls+=1;return "next"
	active=false
	if winners.size()==1:return "winner"
	return "empty" if winners.is_empty() else "ambiguous"
func metrics():
	var requested=0
	for page in pages.slice(0,mini(calls,pages.size())):requested+=page.get("map",{}).size()
	return {"observed":int(coverage.get("observed",0)),"eligible":int(coverage.get("eligible",0)),"prepared_controls":int(coverage.get("covered",0)),"oversized":int(coverage.get("oversized",0)),"candidate_pages":int(coverage.get("pages",0)),"planned_pages":pages.size(),"page_requests":calls,"requested_controls":requested}
func clear():coverage={};pages=[];index=0;winners=[];active=false;calls=0
