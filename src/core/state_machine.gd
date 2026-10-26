extends RefCounted
var current = "idle"
const EDGES = {
	"idle": ["thinking", "executing"],
	"thinking": ["speaking", "idle", "error"],
	"executing": ["idle", "error"],
	"speaking": ["idle", "error"],
	"error": ["idle"]
}

func transition(next):
	if next not in EDGES.get(current, []):
		return false
	current = next
	return true

func reset():
	current = "idle"

