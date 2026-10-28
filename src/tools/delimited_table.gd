extends RefCounted
## Strict bounded CSV/TSV parser retaining original character spans for one-cell edits.
const MAX_BYTES=1048576
const MAX_ROWS=10000
const MAX_COLS=256
const MAX_CELLS=50000
static func parse(text,separator):
	if not text is String or separator not in [",","\t"] or text.to_utf8_buffer().size()>MAX_BYTES:return {"ok":false,"status":"table_invalid"}
	var rows=[];var row=[];var i=0;var cells=0
	while true:
		var start=i;var value="";var quoted=i<text.length() and text[i]=='"'
		if quoted:
			i+=1;var closed=false
			while i<text.length():
				if text[i]=='"':
					if i+1<text.length() and text[i+1]=='"':value+='"';i+=2;continue
					i+=1;closed=true;break
				value+=text[i];i+=1
			if not closed:return {"ok":false,"status":"table_invalid"}
		else:
			while i<text.length() and text[i] not in [separator,"\r","\n"]:
				if text[i]=='"':return {"ok":false,"status":"table_invalid"}
				value+=text[i];i+=1
		row.append({"start":start,"end":i,"value":value,"quoted":quoted});cells+=1
		if row.size()>MAX_COLS or cells>MAX_CELLS:return {"ok":false,"status":"table_limit"}
		if i==text.length():rows.append(row);break
		if text[i]==separator:i+=1;continue
		if text[i] not in ["\r","\n"]:return {"ok":false,"status":"table_invalid"}
		if text[i]=="\r":
			if i+1>=text.length() or text[i+1]!="\n":return {"ok":false,"status":"table_invalid"}
			i+=1
		i+=1;rows.append(row);row=[]
		if rows.size()>=MAX_ROWS and i<text.length():return {"ok":false,"status":"table_limit"}
		if i==text.length():break
	if rows.size()>MAX_ROWS:return {"ok":false,"status":"table_limit"}
	var width=rows[0].size()
	for record in rows:
		if record.size()!=width:return {"ok":false,"status":"table_invalid"}
	return {"ok":true,"rows":rows,"columns":width}
static func encode(value,separator,quoted=false):
	if quoted or separator in value or '"' in value or "\n" in value or "\r" in value:return '"'+value.replace('"','""')+'"'
	return value
static func formula(value):
	var trimmed=value.strip_edges()
	return not trimmed.is_empty() and trimmed[0] in ["=","+","-","@"]
