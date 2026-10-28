extends RefCounted
## Small bounded lexical selection over already captured data; no semantic retrieval guarantee.
const MAX_BLOCKS=48
const MAX_TEXT=400
const MAX_TERMS=32
static func terms(question):
 var result=[]
 var rx=RegEx.new();rx.compile('[\\p{L}\\p{N}]+')
 var stop=['what','when','where','which','this','that','does','with','from','about','please','the','and','are','how','что','когда','какой','какая','какие','сколько','этом','этого','окно','окне','прочитай','пожалуйста','在哪','什么','多少','这个','窗口','请问']
 for hit in rx.search_all(question.to_lower().left(600)):
  var word=hit.get_string()
  var cjk=false
  for character in word:
   if character.unicode_at(0)>=0x3400 and character.unicode_at(0)<=0x9fff:cjk=true;break
  if cjk:
   for i in range(word.length()-1):
    var part=word.substr(i,2)
    if part not in stop and part not in result and result.size()<MAX_TERMS:result.append(part)
  elif word.length()>=3 and word not in stop and word not in result and result.size()<MAX_TERMS:result.append(word)
 return result
static func rank(question,blocks):
 var keywords=terms(question);var rows=[];var seen={}
 for index in range(mini(MAX_BLOCKS,blocks.size())):
  var block=blocks[index]
  if not block is Dictionary or not block.get('text') is String or block.get('kind') not in ['text','control']:continue
  var text=block.text.strip_edges().left(MAX_TEXT)
  if text.is_empty():continue
  var key=text.to_lower()
  if seen.has(key):continue
  seen[key]=true
  var score=0
  for word in keywords:
   if word in key:score+=10
  rows.append({'text':text,'kind':block.kind,'score':score+(2 if block.kind=='text' else 0),'index':index})
 rows.sort_custom(func(a,b):return a.score>b.score if a.score!=b.score else a.index<b.index)
 return rows
static func take(question,blocks,max_bytes,max_rows=18):
 var rows=[];var map={};var omitted=false
 for candidate in rank(question,blocks):
  var row={'id':'r'+str(rows.size()),'kind':candidate.kind,'text':candidate.text}
  var trial=rows.duplicate();trial.append(row)
  if rows.size()>=max_rows or JSON.stringify(trial).to_utf8_buffer().size()>max_bytes:omitted=true;continue
  rows.append(row);map[row.id]=row.text
 return {'rows':rows,'map':map,'selection_partial':omitted or blocks.size()>MAX_BLOCKS}
