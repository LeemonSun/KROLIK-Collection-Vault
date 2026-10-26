extends RefCounted
## Universal context buffer; no application-specific recognizer is required.
## Only caller-supplied observations are handled. This is not a capture adapter.
var latest = {}
var last_timestamp = -1
var allowed_scope = "none"
var min_interval_ms = 1500

func grant_scope(scope):
	if scope not in ["selected_window", "selected_region", "desktop"]:
		return false
	allowed_scope = scope
	clear()
	return true

func revoke():
	allowed_scope = "none"
	clear()

func clear():
	latest = {}
	last_timestamp = -1

func accept(observation):
	if allowed_scope == "none":
		return {"ok": false, "reason": "no_capture_consent"}
	if not (observation is Dictionary):
		return {"ok": false, "reason": "invalid_observation"}
	if observation.get("schema_version") != 1:
		return {"ok": false, "reason": "unsupported_schema"}
	if observation.get("scope") != allowed_scope:
		return {"ok": false, "reason": "scope_mismatch"}
	if not (observation.get("timestamp_ms") is int) or not (observation.get("application_id") is String):
		return {"ok": false, "reason": "invalid_observation"}
	var stamp = observation.timestamp_ms
	if last_timestamp >= 0 and stamp <= last_timestamp:
		return {"ok": false, "reason": "stale_observation"}
	if last_timestamp >= 0 and stamp - last_timestamp < min_interval_ms:
		return {"ok": false, "reason": "throttled"}
	latest = observation.duplicate(true)
	last_timestamp = stamp
	return {"ok": true, "reason": "accepted"}

func context_at(now_ms, max_age_ms = 10000):
	if latest.is_empty() or now_ms < last_timestamp or now_ms - last_timestamp > max_age_ms:
		return {"available": false}
	return {"available": true, "observation": latest.duplicate(true)}

