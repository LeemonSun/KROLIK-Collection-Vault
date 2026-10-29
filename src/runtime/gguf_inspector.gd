extends RefCounted
## Bounded metadata inspection only, not proof of tensor integrity or model quality.
var file
var valid=true
func _string(limit=4194304):
	if file.get_position()+8>file.get_length():valid=false;return ""
	var length=file.get_64()
	if length<0 or length>limit or file.get_position()+length>file.get_length():valid=false;return ""
	return file.get_buffer(length).get_string_from_utf8()
func _skip(kind,depth=0):
	if not valid:return
	var sizes={0:1,1:1,2:2,3:2,4:4,5:4,6:4,7:1,10:8,11:8,12:8}
	if sizes.has(kind):
		var target=file.get_position()+sizes[kind]
		if target>file.get_length():valid=false;return
		file.seek(target)
	elif kind==8:
		_string()
	elif kind==9 and depth==0:
		if file.get_position()+12>file.get_length():valid=false;return
		var element=file.get_32();var count=file.get_64()
		if count<0 or count>1048576 or element==9:valid=false;return
		if sizes.has(element):
			var target=file.get_position()+count*sizes[element]
			if target>file.get_length():valid=false;return
			file.seek(target)
		else:
			for i in range(count):
				_skip(element,1)
				if not valid:return
	else:valid=false
func inspect(path):
	valid=true
	if not path.to_lower().ends_with(".gguf"):return {}
	file=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()<24 or file.get_length()>12*1024*1024*1024:return {}
	if file.get_buffer(4).get_string_from_ascii()!="GGUF":return {}
	var version=file.get_32();var tensors=file.get_64();var count=file.get_64()
	if version not in [2,3] or tensors<=0 or tensors>1000000 or count<=0 or count>4096:return {}
	var result={"bytes":file.get_length(),"mtime":FileAccess.get_modified_time(path),"version":version}
	for i in range(count):
		var key=_string(256)
		if not valid or file.get_position()+4>file.get_length():return {}
		var kind=file.get_32()
		if key in ["general.architecture","general.name","general.size_label"] and kind==8:
			result[key]=_string(512)
		elif key=="split.count" and kind in [2,4]:
			var parts=file.get_16() if kind==2 else file.get_32()
			if parts>1:return {}
		else:_skip(kind)
		if not valid:return {}
	file.close();file=null
	return result if not str(result.get("general.architecture","")).is_empty() else {}
