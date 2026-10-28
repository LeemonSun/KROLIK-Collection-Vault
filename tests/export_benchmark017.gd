extends SceneTree
func _initialize():
 var knowledge=preload('res://src/core/self_knowledge.gd').new()
 var rows=[]
 for spec in [['ru','logic','«Это предложение ложно». Истинно оно или нет? Объясни кратко.'],['en','logic','"This sentence is false." Is it true or false? Explain briefly.'],['zh-Hans','logic','“这句话是假的。”它是真还是假？请简短解释。'],['ru','draft','Составь короткое приглашение на встречу завтра. Не добавляй время или место, которых я не указал. Одно предложение.'],['en','draft','Write a short invitation to a meeting tomorrow. Do not add a time or location that I did not specify. One sentence.'],['zh-Hans','draft','请写一句邀请明天参加会议的话。不要添加我未指定的时间或地点。']]:
  rows.append({'id':spec[0]+'_'+spec[1],'locale':spec[0],'category':spec[1],'messages':[{'role':'system','content':knowledge.factual_text(spec[0])},{'role':'user','content':spec[2]}]})
 var file=FileAccess.open(OS.get_environment('LEEMON_BENCH_FIXTURE'),FileAccess.WRITE);file.store_string(JSON.stringify(rows,'  '));file.close();quit()
