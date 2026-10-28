extends SceneTree
func _initialize():run.call_deferred()
func run():
 var knowledge=preload('res://src/core/self_knowledge.gd').new()
 var inputs={
 'ru':[
 ['liar','Предложение «это предложение ложно» истинно или ложно в классической двузначной логике? Объясни коротко.','Neither consistent classical truth assignment; explain contradiction, not simply false.'],
 ['negative','Все зоры синие. Некоторые синие вещи круглые. Следует ли, что некоторые зоры круглые? Объясни.','No; blue round things may all be non-zors.'],
 ['arithmetic','Заказали7тетрадей по36рублей. Заплатили500рублей, ещё дали скидку10% от стоимости тетрадей. Сколько сдачи? Покажи короткий расчёт.','273.2 change:252 subtotal,226.8afterdiscount.'],
 ['plan','Есть инструменты: прочитать файл, создать резервную копию, заменить точный фрагмент. Нужно поменять Fullscreen=1 на Fullscreen=0 в конфиге, не потеряв остальные настройки. Дай порядок действий и условие остановки, если строка найдена дважды. Ничего не выполняй.','Read actual file, backup before patch, unique exact match else stop/clarify, verify reread; no invented success.'],
 ['typo','хачу чьтоб ты аткрыл докумет и испраил ашипки, но сам текст я не прислал и к окну доступ не дал. Чё сначала надо?','Ask for selected document/access/text; no invented file contents or completion.'],
 ['context','Раньше я назвал проект Лист. Теперь переименовал его в Маяк. Как он называется сейчас? Ответь только названием.','Маяк'],
 ['constraint','Выдай ровно3пункта: одно отличие оперативной памяти от диска, один пример того что теряется при отключении питания и один вопрос ко мне. Без вступления.','Exactly3items, RAMvolatile vs diskpersistent, unsaveddata, onequestion; no refusal.']],
 'en':[
 ['liar','Is the sentence “this sentence is false” true or false in classical two-valued logic? Explain briefly.','Neither consistent classical truth assignment; explain contradiction.'],
 ['negative','All zors are blue. Some blue things are round. Does it follow that some zors are round? Explain.','No; blue round things may all be non-zors.'],
 ['arithmetic','Seven notebooks cost36credits each. I pay500credits and get a10% discount on the notebook subtotal. How much change? Show a short calculation.','273.2change;252subtotal,226.8afterdiscount.'],
 ['plan','Available tools: read a file, make a backup, replace an exact fragment. Change Fullscreen=1 to Fullscreen=0 in a config without losing other settings. Give the order and when to stop if the line occurs twice. Execute nothing.','Read, backup before edit, unique match else stop, verify reread; no fake completion.'],
 ['typo','plz opn my doc n fix the typos. I have not supplied text or granted a document/window. What do you need first?','Ask for document/access/text, no imaginary contents or completion.'],
 ['context','I called the project Leaf earlier. I have renamed it Beacon. What is its current name? Reply with only the name.','Beacon'],
 ['constraint','Give exactly3items: one difference between RAM and disk, one example of data lost on power failure, and one question for me. No introduction.','Exactly3items:volatile/persistent, unsaveddata, onequestion.']],
 'zh-Hans':[
 ['liar','在经典二值逻辑中，“这句话是假的”是真的还是假的？简要说明。','Neither consistent classical truth assignment; explain contradiction.'],
 ['negative','所有佐尔都是蓝色的。有些蓝色物体是圆的。能否推出有些佐尔是圆的？请解释。','No; blue round things may all be non-zors.'],
 ['arithmetic','买7本笔记本，每本36积分。笔记本总价打九折，支付500积分，应找回多少？简要列出计算。','273.2change;252subtotal,226.8afterdiscount.'],
 ['plan','可用工具：读取文件、创建备份、精确替换片段。要把配置中的Fullscreen=1改为Fullscreen=0，并保留其他设置。请给出顺序，以及该行出现两次时应何时停止。不要执行。','Read, backup before edit, unique match else stop, verify reread; no fake completion.'],
 ['typo','请打开我的文档改错字，但我没有提供文本，也没有授权窗口或文档。首先需要什么？','Ask for document/access/text, no imaginary contents or completion.'],
 ['context','我之前把项目叫作“叶子”，现在改名为“灯塔”。目前叫什么？只回答名称。','灯塔'],
 ['constraint','只给出3项：内存和磁盘的一个区别；断电时丢失的数据的一个例子；向我提出一个问题。不要开场白。','Exactly3items:volatile/persistent, unsaveddata, onequestion.']]}
 var rows=[]
 for locale in inputs:
  for spec in inputs[locale]:
   rows.append({'id':locale+'_'+spec[0],'locale':locale,'category':spec[0],'messages':[{'role':'system','content':knowledge.factual_text(locale)},{'role':'user','content':spec[1]}],'input':spec[1],'rubric':spec[2],'max_tokens':256})
 var prior=JSON.parse_string(FileAccess.get_file_as_string('res://research/quality020-cases.json'))
 for spec in prior:
  if spec.category=='uia':rows.append({'id':spec.id,'locale':spec.locale,'category':'uia','messages':spec.messages,'input':spec.input,'rubric':spec.manual_rubric,'expected_choice':spec.expected_choice,'expected_text':spec.expected_text,'schema':spec.options.response_schema,'max_tokens':256})
 var f=FileAccess.open('res://research/brain021-cases.json',FileAccess.WRITE);f.store_string(JSON.stringify(rows,'  '));f.close();print('EXPORTED_BRAIN021 ',rows.size());quit()
