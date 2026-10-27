extends RefCounted
## User-requested new UTF-8 documents only. Existing files are never selected or overwritten.
var directory=""
func _init():
	var documents=OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if not documents.is_empty():directory=documents.path_join("Leemon")
func create_text(text):
	if directory.is_empty() or not text is String or text.to_utf8_buffer().size()>8192:return {"ok":false}
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:return {"ok":false}
	var suffix=Crypto.new().generate_random_bytes(8).hex_encode()
	var stamp=Time.get_datetime_string_from_system().replace(":","-")
	var name="Leemon-"+stamp+"-"+suffix+".txt"
	var path=directory.path_join(name)
	if FileAccess.file_exists(path):return {"ok":false}
	var file=FileAccess.open(path,FileAccess.WRITE)
	if not file:return {"ok":false}
	file.store_buffer(text.to_utf8_buffer());file.close()
	if FileAccess.get_file_as_string(path)!=text:return {"ok":false}
	return {"ok":true,"name":name,"path":path,"sha256":FileAccess.get_sha256(path)}

func create_docx(text):
	if directory.is_empty() or not text is String or text.to_utf8_buffer().size()>8192:return {"ok":false}
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:return {"ok":false}
	var name="Leemon-"+Time.get_datetime_string_from_system().replace(":","-")+"-"+Crypto.new().generate_random_bytes(8).hex_encode()+".docx"
	var path=directory.path_join(name)
	if FileAccess.file_exists(path):return {"ok":false}
	var paragraphs=""
	for line in text.split("\n"):
		paragraphs+='<w:p><w:r><w:t xml:space="preserve">'+line.xml_escape()+'</w:t></w:r></w:p>'
	var parts={
		"[Content_Types].xml":'<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
		"_rels/.rels":'<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="document" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
		"word/document.xml":'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'+paragraphs+'<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>'
	}
	var zip=ZIPPacker.new()
	if zip.open(path)!=OK:return {"ok":false}
	for member in parts:
		if zip.start_file(member)!=OK or zip.write_file(parts[member].to_utf8_buffer())!=OK:
			zip.close();DirAccess.remove_absolute(path);return {"ok":false}
		zip.close_file()
	if zip.close()!=OK:DirAccess.remove_absolute(path);return {"ok":false}
	return {"ok":true,"name":name,"path":path,"sha256":FileAccess.get_sha256(path)}
