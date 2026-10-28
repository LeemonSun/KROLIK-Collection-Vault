extends RefCounted
## Literal replacement within one plain paragraph, including adjacent styled runs.
## Only affected text nodes change. Replacement inherits the first affected run.
static func all_matches(pattern,text):
	var re=RegEx.new();re.compile("(?s)"+pattern);return re.search_all(text)

static func plan(xml,find,replacement):
	var candidates=[]
	for paragraph in all_matches('<w:p(?:\\s[^>]*)?>.*?</w:p>',xml):
		var text=paragraph.get_string();var nodes=[];var joined=""
		for node in all_matches('<w:t(?:\\s[^>]*)?>([^<]*)</w:t>',text):
			var value=node.get_string(1).xml_unescape()
			nodes.append({"match":node,"start":joined.length(),"value":value})
			joined+=value
		var at=joined.find(find)
		while at>=0:
			candidates.append({"paragraph":paragraph,"nodes":nodes,"at":at,"text":text})
			at=joined.find(find,at+1) # Overlapping occurrences are ambiguous too.
	if candidates.size()!=1:return {"ok":false,"status":"office_text"}
	var candidate=candidates[0];var text=candidate.text
	# Do not span fields, drawings, hyperlinks, hidden text, bookmarks or revisions.
	if not all_matches('<w:(?:vanish|webHidden|specVanish)(?:\\s|/|>)',text).is_empty():return {"ok":false,"status":"office_text"}
	var structural=text
	for pattern in ['<w:pPr(?:\\s[^>]*)?>.*?</w:pPr>','<w:rPr(?:\\s[^>]*)?>.*?</w:rPr>','<w:(?:pPr|rPr)(?:\\s[^>]*)?/>','<w:t(?:\\s[^>]*)?>[^<]*</w:t>','</?w:(?:p|r)(?:\\s[^>]*)?>']:
		var re=RegEx.new();re.compile("(?s)"+pattern);structural=re.sub(structural,"",true)
	if not structural.strip_edges().is_empty():return {"ok":false,"status":"office_text"}
	var edits=[];var begin=int(candidate.at);var finish=begin+find.length();var inserted=false
	for node in candidate.nodes:
		var a=int(node.start);var b=a+node.value.length()
		if a>=finish or b<=begin:continue
		var value=node.value.left(maxi(0,begin-a))
		if not inserted:value+=replacement;inserted=true
		value+=node.value.substr(mini(node.value.length(),maxi(0,finish-a)))
		var match_=node.match
		var tag=match_.get_string().left(match_.get_start(1)-match_.get_start())
		if "xml:space=" not in tag:tag=tag.trim_suffix(">")+' xml:space="preserve">'
		edits.append({"start":match_.get_start(),"end":match_.get_end(),"value":tag+value.xml_escape()+"</w:t>"})
	edits.reverse()
	for edit in edits:text=text.left(edit.start)+edit.value+text.substr(edit.end)
	var paragraph=candidate.paragraph
	return {"ok":true,"xml":xml.left(paragraph.get_start())+text+xml.substr(paragraph.get_end())}
