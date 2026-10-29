extends RefCounted
## Extra effect filtering; not a complete semantic security boundary.
static func permitted(name,goal):
	if not preload("res://src/core/intent_constraints.gd").permits_control(name,goal):return false
	var text=str(name).to_lower();var user=str(goal).to_lower()
	for group in [["delete","remove","erase","format","reset","удал","стер","формат","сброс","删除","重置","格式化"],["send","submit","publish","upload","отправ","опубликов","发送","发布","上传"],["pay","buy","purchase","оплат","купить","支付","购买"],["install","uninstall","установ","卸载","安装"]]:
		if group.any(func(word):return word in text) and not group.any(func(word):return word in user):return false
	return true
