extends RefCounted
## Geometry and app state only. No camera/microphone or model work in idle frames.
static func beside(anchor,bounds,extent,current):
	var candidates=[Vector2i(anchor.position.x-extent.x-12,anchor.end.y-extent.y),Vector2i(anchor.end.x+12,anchor.end.y-extent.y)]
	var best=current;var distance=INF
	for point in candidates:
		point.y=clampi(point.y,bounds.position.y,maxi(bounds.position.y,bounds.end.y-extent.y))
		var rect=Rect2i(point,extent)
		if not bounds.encloses(rect) or rect.intersects(anchor.grow(4)):continue
		var travel=Vector2(point).distance_squared_to(Vector2(current))
		if travel<distance:best=point;distance=travel
	return best
static func activity(app):
	if app.paused:return "sleep"
	if app.speech_input.busy():return "listen"
	if app.goal_mode=="proposal":return "wait"
	if app.goal_mode in ["observing","verifying"] or app.window_read_mode=="observing":return "scan"
	if app.goal_mode in ["executing","confirming"]:return "point"
	if not app.window_read_mode.is_empty():return "read"
	if not app.goal_mode.is_empty() or not app.queued_chat_text.is_empty() or app.state.current=="thinking":return "thinking"
	if app.state.current=="executing":return "scan"
	return "idle"
