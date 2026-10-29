extends RefCounted
## Explicit copy of all retained conversation, including visible ephemeral messages.
const MAX_BYTES=4194304
static func format(messages,user_title,truncated=false,notice=""):
	var parts=PackedStringArray(["LEEMON"])
	if truncated:parts.append(notice)
	for message in messages:
		if not message is Dictionary or not message.get("text") is String:return {"ok":false}
		var title=user_title if message.get("speaker")=="user" else "LEEMON"
		if message.get("speaker")=="assistant" and message.get("model_name") is String:
			title+=" · "+message.model_name+" · %.2f s" %(float(message.get("response_ms",0))/1000.0)
		parts.append(title+"\n"+message.text)
	var text="\n\n".join(parts)
	if text.to_utf8_buffer().size()>MAX_BYTES:return {"ok":false}
	return {"ok":true,"text":text,"count":messages.size(),"truncated":truncated}
