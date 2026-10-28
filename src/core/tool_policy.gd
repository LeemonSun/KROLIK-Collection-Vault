extends RefCounted
## Trusted tool registry controls effects; model text is never executed.
const TOOLS = {
	"access.goal":{"implemented":true,"confirmation":false},
	"access.inspect":{"implemented":true,"confirmation":false},
	"access.invoke":{"implemented":true,"confirmation":false},
	"access.write":{"implemented":true,"confirmation":false},
	"screen.describe":{"implemented":true,"confirmation":false},
	"documents.create":{"implemented":true,"confirmation":false},
	"clock.now":{"implemented":true,"confirmation":false},
	"reminders.add":{"implemented":true,"confirmation":false},
	"reminders.list":{"implemented":true,"confirmation":false},
	"clipboard.translate":{"implemented":true,"confirmation":false},
	"companion.walk":{"implemented":true,"confirmation":false},
	"browser.search": {"implemented": true, "confirmation": false},
	"timer.start": {"implemented": true, "confirmation": false},
	"notes.add": {"implemented": true, "confirmation": false},
	"notes.list": {"implemented": true, "confirmation": false},
	"notes.clear": {"implemented": true, "confirmation": true},
	"apps.open": {"implemented": true, "confirmation": false},
	"files.read_selected": {"implemented": false, "confirmation": false},
	"files.delete": {"implemented": false, "confirmation": true},
	"messages.send": {"implemented": false, "confirmation": true},
	"purchase": {"implemented": false, "confirmation": true}
}

func evaluate(tool_id, user_confirmed = false):
	if not TOOLS.has(tool_id):
		return {"allowed": false, "reason": "unknown_tool"}
	var rule = TOOLS[tool_id]
	if not rule.implemented:
		return {"allowed": false, "reason": "not_implemented"}
	if rule.confirmation and not user_confirmed:
		return {"allowed": false, "reason": "confirmation_required"}
	return {"allowed": true, "reason": "ok"}

