extends RefCounted
## Correct only one typo in a known leading action verb. Never rewrite the user's payload.
const ACTIONS=["открой","запусти","найди","поищи","нажми","впиши","допиши","запомни","напомни","создай","open","launch","click","write","append","remember"]
const OTHER=["закрой","удали","сотри","выйди","опиши","объясни","расскажи","покажи","сравни","скажи","delete","close","erase","remove","send","type","describe","explain","show","review","copy"]
static func one_edit(a,b):
	if a==b or absi(a.length()-b.length())>1:return false
	if a.length()==b.length():
		var different=[]
		for i in range(a.length()):
			if a[i]!=b[i]:different.append(i)
		return different.size()==1 or (different.size()==2 and different[1]==different[0]+1 and a[different[0]]==b[different[1]] and a[different[1]]==b[different[0]])
	var short_=a if a.length()<b.length() else b
	var long_=b if a.length()<b.length() else a
	var i=0;var j=0;var skipped=false
	while i<short_.length() and j<long_.length():
		if short_[i]==long_[j]:i+=1;j+=1
		elif skipped:return false
		else:skipped=true;j+=1
	return true
static func normalize(raw):
	var text=raw.strip_edges();var space=text.find(" ")
	if space<0:return text
	var head=text.left(space).to_lower()
	if head.length()<4 or head in ACTIONS or head in OTHER:return text
	var candidates=[]
	for word in ACTIONS+OTHER:
		if one_edit(head,word):candidates.append(word)
	if candidates.size()!=1 or candidates[0] not in ACTIONS:return text
	return candidates[0]+text.substr(space)
