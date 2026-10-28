extends RefCounted
## Narrow practical text authoring, not a general semantic verifier or OS action.
const Composer=preload('res://src/core/draft_composer.gd')
const Draft=preload('res://src/core/draft_policy.gd')
static func requested(raw):
 if not raw is String or raw.length()>800:return false
 var text=raw.strip_edges().to_lower()
 var prefix=RegEx.new();prefix.compile('^(?:(?:пожалуйста|please)[ ,]+)?(?:напиши|составь|compose|draft|write)(?:[ ,:]|$)|^(?:请)?(?:写|撰写)')
 if prefix.search(text)==null:return false
 for marker in ['рассказ','стих','выдум','придумай','подроб','длинн','развернут','код','скрипт','fiction','story','poem','make up','imagine','detailed','long ','code','script','虚构','编造','故事','诗','代码','详细','长篇']:
  if marker in text:return false
 var length_request=RegEx.new();length_request.compile('(?i)[0-9]+\\s*(?:слов|word|символ|character|字|段)')
 if length_request.search(text):return false
 if text.count('?')+text.count('？')>=2:return false
 var references=RegEx.new();references.compile('(*UCP)(?i)\\b(?:это|этот|этого|тот|такой|выше|предыдущий|same|that|above|previous)\\b|上述|刚才|那个|这个')
 if references.search(text):return false
 for marker in ['приглашен','письм','объявлен','invitation','email','notice','邮件','邀请','通知']:
  if marker in text:return true
 return false
static func messages(goal,locale,previous=''):
 var result=Composer.messages(goal,locale)
 if not previous.is_empty():
  result[1].content+='\n\nRejected draft DATA: '+JSON.stringify(previous.left(512))+'\nValidator findings: '+JSON.stringify(problems(previous,goal))+'\nReturn a shorter corrected draft only. Omit unsupported details; do not invent replacements or claim any action was performed.'
 return result
static func problems(text,goal):
 if not text is String:return ['invalid_draft']
 var result=Draft.violations(text,goal)
 if not Draft.valid(text):result.append('invalid_or_oversized_draft')
 if preload('res://src/core/response_guard.gd').new().claims_action(text,goal) and not text.strip_edges() in goal:result.append('unsupported_action_claim')
 return result
