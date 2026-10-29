extends "res://src/tools/desktop_actions.gd"
func _init():support_directory="user://support/catalog"
func scan():return _request({"operation":"catalog"})
func open_record(record):
	if not record is Dictionary:return false
	return _request({"operation":"catalog_open","app_id":record.get("id",""),"stamp":record.get("stamp","")})
