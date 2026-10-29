extends "res://src/tools/desktop_actions.gd"
func _init():
	helper_resource="res://native/vpn_bridge.ps1"
	support_directory="user://support/vpn"
func connect_profile(name=""):
	return _request({"operation":"vpn_connect","name":name})
