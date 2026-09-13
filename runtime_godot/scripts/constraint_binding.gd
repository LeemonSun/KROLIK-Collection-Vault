class_name VaultConstraintBinding
extends RefCounted

var joint := ""
var prop_id := 0
var anchor := "center"
var enabled := true
var strength := 1.0

func from_dict(data: Dictionary) -> VaultConstraintBinding:
    joint = str(data.get("joint", joint))
    prop_id = int(data.get("prop_id", prop_id))
    anchor = str(data.get("anchor", anchor))
    enabled = bool(data.get("enabled", enabled))
    strength = clampf(float(data.get("strength", strength)), 0.0, 1.0)
    return self
