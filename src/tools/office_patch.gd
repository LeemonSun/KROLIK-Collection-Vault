extends "res://src/tools/text_patch.gd"
## Bounded OOXML parts; no Office installation, macros, shell or model required.
const MAX_EXPANDED=8388608
static func xml_ok(text):
	if "<!" in text or text.to_utf8_buffer().size()>2097152:return false
	var parser=XMLParser.new();var stack=[]
	if parser.open_buffer(text.to_utf8_buffer())!=OK:return false
	var result=parser.read()
	while result==OK:
		if parser.get_node_type()==XMLParser.NODE_ELEMENT and not parser.is_empty():stack.append(parser.get_node_name())
		elif parser.get_node_type()==XMLParser.NODE_ELEMENT_END:
			if stack.is_empty() or stack.pop_back()!=parser.get_node_name():return false
		result=parser.read()
	return result==ERR_FILE_EOF and stack.is_empty()
func _read(path):
	if not path is String or path.get_extension().to_lower() not in ["docx","xlsx"]:return super._read(path)
	if not path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://"):return {"ok":false,"status":"unsupported"}
	var directory=DirAccess.open(path.get_base_dir())
	if directory and directory.is_link(path.get_file()):return {"ok":false,"status":"unsupported"}
	var file=FileAccess.open(path,FileAccess.READ)
	if not file or file.get_length()>MAX_BYTES:return {"ok":false,"status":"unreadable"}
	var bytes=file.get_buffer(file.get_length());file.close()
	return {"ok":true,"bytes":bytes,"text":"SHA-256: "+digest(bytes),"bom":false,"sha":digest(bytes)}
func _restore_preview(bytes):
	if last_backup.get("path","").get_extension().to_lower() in ["docx","xlsx"]:return "SHA-256: "+digest(bytes)
	return super._restore_preview(bytes)
static func inventory(bytes):
	# Validate the central directory BEFORE ZIPReader allocates decompressed data.
	if bytes.size()<22:return {}
	var end=-1
	for i in range(bytes.size()-22,maxi(-1,bytes.size()-65558),-1):
		if bytes.decode_u32(i)==0x06054b50 and i+22+bytes.decode_u16(i+20)==bytes.size():end=i;break
	if end<0 or bytes.decode_u16(end+4)!=0 or bytes.decode_u16(end+6)!=0:return {}
	var count=bytes.decode_u16(end+10);var offset=bytes.decode_u32(end+16);var limit=offset+bytes.decode_u32(end+12)
	if count<1 or count>256 or count!=bytes.decode_u16(end+8) or limit!=end:return {}
	var names={};var total=0
	for _entry in range(count):
		if offset+46>limit or bytes.decode_u32(offset)!=0x02014b50:return {}
		var packed=bytes.decode_u32(offset+20);var expanded=bytes.decode_u32(offset+24)
		var length=bytes.decode_u16(offset+28);var next=offset+46+length+bytes.decode_u16(offset+30)+bytes.decode_u16(offset+32)
		if next>limit or bytes.decode_u16(offset+8)&1 or bytes.decode_u16(offset+10) not in [0,8]:return {}
		var name=bytes.slice(offset+46,offset+46+length).get_string_from_utf8()
		if name.is_empty() or name in names or name.begins_with("/") or ".." in name.split("/") or "\\" in name or ":" in name or name.to_lower().ends_with(".bin") or name.begins_with("_xmlsignatures/"):return {}
		total+=expanded
		if expanded>2097152 or total>MAX_EXPANDED or expanded>maxi(4096,packed*200):return {}
		names[name]=expanded;offset=next
	return names if offset==limit else {}
func parts(path,source):
	var names=inventory(source.bytes)
	if names.is_empty():return {"ok":false,"status":"office_package"}
	var reader=ZIPReader.new()
	if reader.open(path)!=OK:return {"ok":false,"status":"office_package"}
	var entries={};var valid=reader.get_files().size()==names.size()
	for name in names:
		var bytes=reader.read_file(name)
		if bytes.size()!=names[name]:valid=false;break
		entries[name]=bytes
	reader.close()
	if not valid or FileAccess.get_sha256(path)!=source.sha or not entries.has("[Content_Types].xml"):return {"ok":false,"status":"office_package"}
	return {"ok":true,"entries":entries}
static func matches(pattern,text):
	var regex=RegEx.new();regex.compile("(?s)"+pattern);return regex.search_all(text)
func _archive_plan(path,source,entries,part,after,before_value,after_value,line):
	if not xml_ok(after):return {"ok":false,"status":"office_xml"}
	entries[part]=after.to_utf8_buffer()
	var temporary="user://office-"+Crypto.new().generate_random_bytes(16).hex_encode()+".zip"
	var writer=ZIPPacker.new();var valid=writer.open(temporary)==OK
	if not valid:return {"ok":false,"status":"write_failed"}
	for name in entries:
		if name.ends_with("/"):continue
		if writer.start_file(name)!=OK or writer.write_file(entries[name])!=OK or writer.close_file()!=OK:valid=false;break
	if writer.close()!=OK:valid=false
	var bytes=FileAccess.get_file_as_bytes(temporary)
	# Verify every uncompressed part, including all untouched styles and media.
	var verify=ZIPReader.new()
	if verify.open(temporary)!=OK:valid=false
	else:
		for name in verify.get_files():
			if not name.ends_with("/") and not entries.has(name):valid=false
		for name in entries:
			if verify.read_file(name)!=entries[name]:valid=false;break
		verify.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	if not valid or inventory(bytes).is_empty():return {"ok":false,"status":"office_package"}
	return _plan(path,source,bytes,before_value,after_value,line)
func prepare(path,find,replacement):
	if path.get_extension().to_lower()!="docx":return super.prepare(path,find,replacement)
	cancel()
	if not find is String or not replacement is String or find.is_empty() or replacement.to_utf8_buffer().size()>65536 or "\n" in replacement or "\r" in replacement:return {"ok":false,"status":"input"}
	var source=_read(path)
	if not source.ok:return source
	var package=parts(path,source)
	if not package.ok:return package
	var part="word/document.xml";var xml=package.entries.get(part,PackedByteArray()).get_string_from_utf8()
	if not xml_ok(xml) or "<w:document" not in xml or "<w:ins" in xml or "<w:del" in xml:return {"ok":false,"status":"office_xml"}
	var candidates=[]
	for match_ in matches('<w:t(?:\\s[^>]*)?>([^<]*)</w:t>',xml):
		var value=match_.get_string(1).xml_unescape()
		for _i in range(value.count(find)):candidates.append({"match":match_,"value":value})
	if candidates.size()!=1:return {"ok":false,"status":"office_text"}
	var candidate=candidates[0];var match_=candidate.match
	var new_value=candidate.value.replace(find,replacement)
	var escaped=new_value.xml_escape()
	var tag=match_.get_string().substr(0,match_.get_start(1)-match_.get_start())
	# Preserve leading/trailing spaces even when the source omitted xml:space.
	if "xml:space=" not in tag:tag=tag.trim_suffix(">")+' xml:space="preserve">'
	var after=xml.left(match_.get_start())+tag+escaped+'</w:t>'+xml.substr(match_.get_end())
	return _archive_plan(path,source,package.entries,part,after,find,replacement,1)
static func attributes(tag):
	var parser=XMLParser.new();var result={}
	if parser.open_buffer(tag.to_utf8_buffer())!=OK or parser.read()!=OK or parser.get_node_type()!=XMLParser.NODE_ELEMENT:return result
	for i in range(parser.get_attribute_count()):result[parser.get_attribute_name(i)]=parser.get_attribute_value(i)
	return result
static func address(row,column):
	var letters="";var n=column
	while n>0:n-=1;letters=char(65+n%26)+letters;n=n/26
	return letters+str(row)
func prepare_sheet_cell(path,sheet,row,column,expected,replacement,inspect_only=false):
	cancel()
	if sheet<1 or row<1 or row>1048576 or column<1 or column>16384 or replacement.to_utf8_buffer().size()>65536:return {"ok":false,"status":"input"}
	var source=_read(path)
	if not source.ok:return source
	var package=parts(path,source)
	if not package.ok:return package
	var entries=package.entries
	var workbook=entries.get("xl/workbook.xml",PackedByteArray()).get_string_from_utf8()
	var rels=entries.get("xl/_rels/workbook.xml.rels",PackedByteArray()).get_string_from_utf8()
	if not xml_ok(workbook) or not xml_ok(rels):return {"ok":false,"status":"office_xml"}
	var sheets=matches('<sheet\\s[^>]*/>',workbook)
	if sheet>sheets.size():return {"ok":false,"status":"table_address"}
	var selected=attributes(sheets[sheet-1].get_string());var part=""
	for relation in matches('<Relationship\\s[^>]*/>',rels):
		var attrs=attributes(relation.get_string())
		if attrs.get("Id")==selected.get("r:id") and attrs.get("TargetMode","")!="External":
			var target=str(attrs.get("Target",""))
			if target.begins_with("/xl/"):part=target.trim_prefix("/")
			elif not target.begins_with("/") and ".." not in target.split("/"):part="xl/"+target
	if not part.begins_with("xl/worksheets/") or not entries.has(part):return {"ok":false,"status":"office_xml"}
	var xml=entries[part].get_string_from_utf8()
	# Refuse formula workbooks: cached dependent results cannot be verified here.
	for name in entries:
		if name.begins_with("xl/worksheets/") and name.ends_with(".xml"):
			var content=entries[name].get_string_from_utf8()
			if not xml_ok(content) or not matches('<(?:[A-Za-z_][\\w.-]*:)?f(?:\\s|>|/)',content).is_empty():return {"ok":false,"status":"office_formula"}
	if not xml_ok(xml) or "<sheetProtection" in xml:return {"ok":false,"status":"office_xml"}
	var ref=address(row,column);var candidates=[]
	for cell in matches('<c\\s[^>]*(?:/>|>.*?</c>)',xml):
		var tag=cell.get_string().get_slice(">",0)+">"
		if attributes(tag).get("r")==ref:candidates.append(cell)
	if candidates.size()!=1:return {"ok":false,"status":"table_address"}
	var cell=candidates[0];var tag=cell.get_string().get_slice(">",0)+">";var attrs=attributes(tag);var value=""
	if attrs.get("t","")=="inlineStr":
		for text in matches('<t(?:\\s[^>]*)?>([^<]*)</t>',cell.get_string()):value+=text.get_string(1).xml_unescape()
	else:
		var values=matches('<v>([^<]*)</v>',cell.get_string())
		value=values[0].get_string(1).xml_unescape() if values.size()==1 else ""
		if attrs.get("t")=="s":
			var strings=entries.get("xl/sharedStrings.xml",PackedByteArray()).get_string_from_utf8()
			var items=matches('<si(?:\\s[^>]*)?>.*?</si>',strings)
			if not xml_ok(strings) or not value.is_valid_int() or value.to_int()<0 or value.to_int()>=items.size():return {"ok":false,"status":"office_xml"}
			var index=value.to_int();value=""
			for text in matches('<t(?:\\s[^>]*)?>([^<]*)</t>',items[index].get_string()):value+=text.get_string(1).xml_unescape()
	if inspect_only:return {"ok":true,"value":value}
	if value!=expected:return {"ok":false,"status":"changed"}
	for key in attrs:
		if key not in ["r","s","t"]:return {"ok":false,"status":"office_xml"}
	var style=' s="'+str(attrs.s).xml_escape(true)+'"' if attrs.has("s") else ""
	var new_cell='<c r="'+ref+'"'+style+' t="inlineStr"><is><t xml:space="preserve">'+replacement.xml_escape()+'</t></is></c>'
	var after=xml.left(cell.get_start())+new_cell+xml.substr(cell.get_end())
	return _archive_plan(path,source,entries,part,after,expected,replacement,row)
