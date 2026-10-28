extends RefCounted
## Selective bounded deliberation with the SAME owned small model, never extra workers.
## Adoption depends on real semantic evidence; token budget is not an IQ guarantee.
static func wanted(raw):
 if not raw is String or raw.length()>4000:return false
 var text=raw.to_lower().strip_edges()
 for skip in ['без рассуждений','не рассуждай','не думай','без обдумывания','no reasoning','do not reason','without reasoning','不要推理','不要思考']:
  if skip in text:return false
 var literal=RegEx.new();literal.compile('^(?:переведи|translate|repeat|повтори|цитируй|翻译|重复)(?:\\s|[:：]|$)')
 if literal.search(text):return false
 var prefix=RegEx.new();prefix.compile('^(?:(?:пожалуйста|please)[ ,]+)?(?:подумай|обдумай|think|reason)(?:\\s|[:：]|$)|^(?:请)?(?:仔细思考|认真思考|推理)')
 if prefix.search(text):return true
 for marker in ['следует ли','можно ли вывести','логический вывод','логическое противоречие','парадокс','докажи','план действий','порядок действий','does it follow','logical contradiction','paradox','prove that','order of actions','plan of action','能否推出','逻辑矛盾','悖论','证明','操作顺序']:
  if marker in text:return true
 return false
static func apply(raw,options,owned):
 var result=options.duplicate(true)
 if not owned or not wanted(raw) or result.has('response_schema') or result.get('multimodal',false):return result
 result['reasoning_tokens']=128
 result['max_tokens']=mini(384,maxi(192,int(result.get('max_tokens',96))))
 result['companion_dialogue']=false
 return result
