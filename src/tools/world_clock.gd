extends RefCounted
var data={}
func _init():
	data=JSON.parse_string(FileAccess.get_file_as_string("res://config/world_clock.json"))
func normalize(text):
	var rx=RegEx.new();rx.compile("[^\\p{L}\\p{N}]")
	return rx.sub(text.to_lower().replace("ё","е"),"",true)
func resolve(city,now=-1):
	if now<0:now=int(Time.get_unix_time_from_system())
	var key=normalize(city)
	if key in ["local","здесь","тут","местное","本地"]:
		return _format(city,now,int(Time.get_time_zone_from_system().get("bias",0))*60,"local")
	var names=data.get("aliases",{}).get(key,[])
	if names.is_empty():return {"ok":false,"status":"missing"}
	if names.size()>1:return {"ok":false,"status":"ambiguous","choices":names}
	if now<int(data.get("valid_from",0)) or now>=int(data.get("valid_until",0)):return {"ok":false,"status":"expired"}
	var zone=names[0]
	var transitions=data.zones[zone].transitions
	var low=0;var high=transitions.size()
	while low+1<high:
		var middle=(low+high)/2
		if int(transitions[middle][0])<=now:low=middle
		else:high=middle
	return _format(city,now,int(transitions[low][1]),zone)
func _format(city,stamp,offset,zone):
	var value=Time.get_datetime_dict_from_unix_time(stamp+offset)
	var sign="+" if offset>=0 else "−"
	var absolute=absi(offset)
	return {"ok":true,"city":city,"zone":zone,"offset":offset,"time":"%02d:%02d" % [value.hour,value.minute],"date":"%04d-%02d-%02d" % [value.year,value.month,value.day],"utc":"UTC%s%02d:%02d" % [sign,absolute/3600,(absolute%3600)/60],"tzdb":data.get("tzdb_version","")}
