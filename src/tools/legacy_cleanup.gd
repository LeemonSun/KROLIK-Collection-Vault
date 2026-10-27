extends RefCounted
## Migration uses exact release hashes, never broad filename patterns or recursive deletion.
func safe_path(base,relative):
	if relative.is_empty() or relative.is_absolute_path() or "\\" in relative:return ""
	var parts=relative.split("/",false)
	var cursor=base
	for part in parts:
		if part in [".",".."] or ":" in part:return ""
		var directory=DirAccess.open(cursor)
		if directory and directory.is_link(part):return ""
		cursor=cursor.path_join(part)
	return cursor
func run(base,archive,manifest):
	var result={"removed":0,"archived":0,"preserved":0}
	if not manifest is Dictionary or manifest.get("schema_version")!=1:return result
	var parents=[]
	for entry in manifest.get("entries",[]):
		var relative=str(entry.get("path",""))
		# The running program and active pack can never be migration targets.
		if relative.get_file().to_lower() in ["companion.exe","companion.pck"]:continue
		var path=safe_path(base,relative)
		if path.is_empty() or not FileAccess.file_exists(path):continue
		if FileAccess.get_sha256(path)!=str(entry.get("sha256","")):
			result.preserved+=1;continue
		if entry.get("action")=="archive":
			DirAccess.make_dir_recursive_absolute(archive)
			var destination=safe_path(archive,relative.get_file())
			if destination.is_empty():result.preserved+=1;continue
			if FileAccess.file_exists(destination) and FileAccess.get_sha256(destination)!=entry.sha256:
				result.preserved+=1;continue
			if not FileAccess.file_exists(destination):
				if DirAccess.copy_absolute(path,destination)!=OK:result.preserved+=1;continue
			if FileAccess.get_sha256(destination)!=entry.sha256:result.preserved+=1;continue
			if DirAccess.remove_absolute(path)==OK:result.archived+=1
		else:
			if DirAccess.remove_absolute(path)==OK:result.removed+=1
		var parent=relative.get_base_dir()
		if not parent.is_empty() and parent!="." and parent not in parents:parents.append(parent)
	for relative in parents:
		var path=safe_path(base,relative)
		if path.is_empty():continue
		var directory=DirAccess.open(path)
		if directory:
			directory.include_hidden=true
			if directory.get_files().is_empty() and directory.get_directories().is_empty():DirAccess.remove_absolute(path)
	return result
