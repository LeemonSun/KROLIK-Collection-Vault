extends RefCounted
## Trusted app facts answer questions about the app; general conversation stays with the LLM.
func _has(text,phrases):
	for phrase in phrases:
		if phrase in text:return true
	return false
func classify(raw):
	var text=raw.to_lower().replace('ё','е').replace('-',' ').strip_edges()
	if _has(text,['точное название модели','какая модель у тебя внутри','what base model','which model file','底层模型','模型文件']):return 'runtime_model'
	if _has(text,['что ты за модель','какая ты модель','ты openai','ты chatgpt','ты чатгпт','what model are you','which model are you','你是什么模型']):return 'model'
	if _has(text,['тебя написал','тебя создал','тебя переписал','чат гпт и уже переписал','who made you','who created you','谁创造了你']):return 'origin'
	if _has(text,['наш чат','чат сохран','чат сохрон','чат обнул','добавил память','добавил тебе память','тебе добавить память','память я тебе добавил','память у тебя','ты запоминаешь','авто память','автопамять','do you remember me','does our chat','do you save our chat','聊天会保存','你有记忆吗']):return 'memory'
	if _has(text,['работаешь от интер','работаешь локально','работаешь без интер','работать без интер','без подключения ты','без подключения к интернету','от интеренете или локально','не будет подключения','are you offline','do you need internet','work without internet','你需要联网','你是离线']):return 'offline'
	if _has(text,['как сильно ты влияешь','какую нагрузку ты','нагрузку оказываешь','нагрузку окзаываешь','ты грузишь','ты нагружаешь','сколько ты потребляешь','your cpu usage','how much ram do you','你占用多少']):return 'load'
	if _has(text,['ты научилась перемещаться','ты умеешь двигаться','ты можешь перемещаться','ты уже научилась сама перемещаться','твои анимации','can you move around','你的动画','你能移动']):return 'motion'
	if _has(text,['за счет чего ты работаешь','как ты работаешь','what powers you','how do you work','你如何运行']):return 'power'
	if _has(text,['что ты умеешь','твои возможности','что у нас можно сделать','что он уже тебе добавил','what can you do','你会做什么']):return 'capabilities'
	if _has(text,['погода сейчас','погода сегодня','какая погода','сколько сейчас градусов','сегодня будет градусов','weather today','weather right now','今天天气','现在天气']):return 'weather'
	if text.rstrip('.!? ') in ['привет','приветик','как дела','как ты','скажи что либо','скажи что-нибудь','скажи что нибудь','скажи что то','hello','hi','how are you','你好','你好吗']:return 'greeting'
	return ''
func answer(raw,app):
	var intent=classify(raw)
	if intent.is_empty():return {}
	var key='self_'+intent
	var model=str(app.local_runtime.manifest.get('model',{}).get('file','')).get_basename()
	if intent=='model':key='self_identity'
	if intent=='runtime_model':
		if app.provider_name=='local_worker':key='self_model_owned'
		elif app.provider_name=='llama_loopback':key='self_model_developer'
		else:key='self_model_inactive'
	if intent=='offline' and app.provider_name=='llama_loopback':key='self_offline_developer'
	if intent=='offline' and not app.local_runtime.installed() and app.provider_name!='llama_loopback':key='self_offline_uninstalled'
	return {'intent':intent,'text':app.t(key,{'model':model,'threads':app.profiles.config(app.profile_name).get('cpu_threads',2)})}
func system_text(locale):
	var language={'ru':'Russian, feminine first person','en':'English','zh-Hans':'Simplified Chinese'}.get(locale,'English')
	return 'You are Signal, a friendly desktop companion. Answer directly in %s, usually in 1-3 sentences. Use general knowledge. Be clear when unsure. Saved notes are about the user. Never claim actions without executor results. You have no live screen vision or web page reading. Never invent your runtime, creator or capabilities.' % language
func response_budget(raw,options):
	var result=options.duplicate(true)
	var text=raw.to_lower()
	if _has(text,['подроб','полный список','развернут','пошаг','in detail','full list','step by step','详细','完整列表']):
		result['max_tokens']=mini(256,maxi(int(options.get('max_tokens',96)),192))
	return result
