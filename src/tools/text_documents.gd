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
