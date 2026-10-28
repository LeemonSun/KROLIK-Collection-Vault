extends RefCounted
## Fixed page IDs only. Opening a page is not changing or verifying a setting.
const PAGES={"display":"display","sound":"sound","bluetooth":"bluetooth","network":"network-status","wifi":"network-wifi","power":"powersleep","microphone":"privacy-microphone","notifications":"notifications","storage":"storagesense","apps":"appsfeatures","update":"windowsupdate","about":"about","privacy":"privacy"}
const ALIASES={"экран":"display","экрана":"display","звук":"sound","звука":"sound","сеть":"network","сети":"network","питание":"power","питания":"power","микрофон":"microphone","микрофона":"microphone","уведомления":"notifications","уведомлений":"notifications","память":"storage","хранилища":"storage","приложения":"apps","приложений":"apps","обновления":"update","обновлений":"update","конфиденциальности":"privacy","系统":"about","显示":"display","声音":"sound","蓝牙":"bluetooth","网络":"network","电源":"power","麦克风":"microphone","通知":"notifications","存储":"storage","更新":"update"}
static func resolve(raw):
	var key=raw.strip_edges().to_lower();key=str(ALIASES.get(key,key))
	return {"ok":true,"id":key,"uri":"ms-settings:"+PAGES[key]} if PAGES.has(key) else {"ok":false,"status":"unsupported"}
static func open_page(raw,opener=Callable(),platform=""):
	var page=resolve(raw)
	if not page.ok:return page
	if (platform if not platform.is_empty() else OS.get_name())!="Windows":return {"ok":false,"status":"platform"}
	var result=opener.call(page.uri) if opener.is_valid() else OS.shell_open(page.uri)
	return {"ok":result==OK,"status":"requested" if result==OK else "failed","id":page.id}
