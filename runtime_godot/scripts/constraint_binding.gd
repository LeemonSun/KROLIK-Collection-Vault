class_name VaultConstraintBinding
extends RefCounted

var joint := ""
var prop_id := 0
var anchor := "center"
var enabled := true
var strength := 1.0
var constraint_kind := "generic"
var discomfort := 0.0
var threat := 0.0
var social_exposure := 0.0
var mobility_limit := 0.0

func from_dict(data: Dictionary) -> VaultConstraintBinding:
    joint = str(data.get("joint", joint))
    prop_id = int(data.get("prop_id", prop_id))
    anchor = str(data.get("anchor", anchor))
    enabled = bool(data.get("enabled", enabled))
    strength = clampf(float(data.get("strength", strength)), 0.0, 1.0)
    constraint_kind = str(data.get("constraint_kind", data.get("kind", constraint_kind)))
    discomfort = clampf(float(data.get("discomfort", discomfort)), 0.0, 1.0)
    threat = clampf(float(data.get("threat", threat)), 0.0, 1.0)
    social_exposure = clampf(float(data.get("social_exposure", social_exposure)), 0.0, 1.0)
    mobility_limit = clampf(float(data.get("mobility_limit", mobility_limit)), 0.0, 1.0)
    return self
