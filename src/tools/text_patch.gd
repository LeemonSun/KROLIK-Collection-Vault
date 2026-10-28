extends RefCounted
## User-selected UTF-8 text only. One-use reviewed patch, backup, conflict detection.
const MAX_BYTES=1048576
const EXTENSIONS=["txt","ini","cfg","conf","json","jsonc","toml","yaml","yml","xml","csv","md","properties","log"]
var backup_directory="user://file-backups-v1"
var pending={}
var last_backup={}
static func digest(bytes):
	var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
func _read(path):
	if not path is String or not path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://"):return {"ok":false,"status":"unsupported"}
	if path.get_extension().to_lower() not in EXTENSIONS:return {"ok":false,"status":"unsupported"}
	var directory=DirAccess.open(path.get_base_dir())
	if directory and directory.is_link(path.get_file()):return {"ok":false,"status":"unsupported"}
	var file=FileAccess.open(path,FileAccess.READ)
	if not file or file.get_length()>MAX_BYTES:return {"ok":false,"status":"unreadable"}
	var bytes=file.get_buffer(file.get_length());file.close()
	if 0 in bytes:return {"ok":false,"status":"encoding"}
	var bom=bytes.slice(0,3)==PackedByteArray([239,187,191])
	var body=bytes.slice(3) if bom else bytes
	var text=body.get_string_from_utf8()
	if text.to_utf8_buffer()!=body:return {"ok":false,"status":"encoding"}
	return {"ok":true,"bytes":bytes,"text":text,"bom":bom,"sha":digest(bytes)}
func prepare(path,find,replacement):
	cancel()
	if not find is String or not replacement is String or find.is_empty() or replacement.to_utf8_buffer().size()>65536:return {"ok":false,"status":"input"}
	var source=_read(path)
	if not source.ok:return source
	if source.text.count(find)!=1:return {"ok":false,"status":"ambiguous"}
	var after=source.text.replace(find,replacement)
	if path.get_extension().to_lower()=="json":
		var parser=JSON.new()
		if parser.parse(after)!=OK:return {"ok":false,"status":"invalid_json"}
	var bytes=after.to_utf8_buffer()
	if source.bom:bytes=PackedByteArray([239,187,191])+bytes
	return _plan(path,source,bytes,find,replacement,source.text.left(source.text.find(find)).count("\n")+1)
func _plan(path,source,bytes,find,replacement,line):
	if bytes.size()>MAX_BYTES or digest(bytes)==source.sha:return {"ok":false,"status":"input"}
	var token=Crypto.new().generate_random_bytes(16).hex_encode()
	pending={"token":token,"path":path,"before":source.sha,"old":source.bytes,"after":digest(bytes),"bytes":bytes,"deadline":Time.get_ticks_msec()+120000}
	return {"ok":true,"token":token,"path":path,"line":line,"before":find.left(1200),"after":replacement.left(1200)}
func commit(token):
	if pending.is_empty() or not token is String or token!=pending.token:return {"ok":false,"status":"approval"}
	var plan=pending;pending={}
	if Time.get_ticks_msec()>plan.deadline or FileAccess.get_sha256(plan.path)!=plan.before:return {"ok":false,"status":"changed"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup_directory))
	var id=(plan.path.sha256_text()+plan.before).sha256_text()
	var backup=backup_directory.path_join(id+".bak")
	if not FileAccess.file_exists(backup):
		var used=0
		for name in DirAccess.get_files_at(backup_directory):
			var f=FileAccess.open(backup_directory.path_join(name),FileAccess.READ)
			if f:used+=f.get_length()
		if used+plan.old.size()>16*MAX_BYTES:return {"ok":false,"status":"backup_full"}
		var save=FileAccess.open(backup,FileAccess.WRITE)
		if not save:return {"ok":false,"status":"backup_failed"}
		save.store_buffer(plan.old);save.flush();save.close()
	if FileAccess.get_sha256(backup)!=plan.before:return {"ok":false,"status":"backup_failed"}
	var temporary=plan.path.get_base_dir().path_join(".leemon-"+Crypto.new().generate_random_bytes(16).hex_encode()+".tmp")
	var file=FileAccess.open(temporary,FileAccess.WRITE)
	if not file:return {"ok":false,"status":"write_failed"}
	file.store_buffer(plan.bytes);file.flush();file.close()
	if FileAccess.get_sha256(temporary)!=plan.after or FileAccess.get_sha256(plan.path)!=plan.before:
		DirAccess.remove_absolute(temporary);return {"ok":false,"status":"changed"}
	var result=DirAccess.rename_absolute(temporary,plan.path)
	if result!=OK:
		DirAccess.remove_absolute(temporary);return {"ok":false,"status":"write_failed"}
	last_backup={"path":plan.path,"backup":backup,"sha":plan.before}
	if FileAccess.get_sha256(plan.path)!=plan.after:return {"ok":false,"status":"unverified"}
	return {"ok":true,"status":"written","path":plan.path}
func prepare_restore():
	cancel()
	if last_backup.is_empty() or FileAccess.get_sha256(last_backup.backup)!=last_backup.sha:return {"ok":false,"status":"backup_failed"}
	var source=_read(last_backup.path)
	if not source.ok:return source
	var old=FileAccess.get_file_as_bytes(last_backup.backup)
	return _plan(last_backup.path,source,old,source.text.left(1200),old.get_string_from_utf8().left(1200),1)
func cancel():pending={}
