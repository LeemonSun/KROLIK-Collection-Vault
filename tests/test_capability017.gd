extends SceneTree
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
class Denied extends RefCounted:
 func evaluate(_id):return {'allowed':false}
func run():
 var app=root.get_node('App');app.cancel();var original=app.messages.size();var calls=app.desktop_actions.last_result.duplicate(true)
 var Catalog=preload('res://src/core/capability_answers.gd')
 for locale in ['ru','en','zh-Hans']:
  app.set_locale(locale)
  for phrase in ['Ты умеешь ставить таймер?','Can you save a note?','你能计算吗？','Can you delete files?','Можешь ли ты редактировать файл?']:
   for i in range(20):
    var answer=app.self_knowledge.answer(phrase,app)
    check(not answer.is_empty() and not answer.text.begins_with('cap_'),'Capabilities stay registry-grounded after repeated questions '+locale)
 check(Catalog.lookup('Can you set a timer?',Denied.new()).key=='cap_unavailable','Registry denial overrides hardcoded descriptions')
 check(Catalog.lookup('1. Can you calculate? 2. Can you see my screen?',app.policy).is_empty(),'Multiquestion request is not swallowed by one tool fact')
 check(Catalog.lookup('Can you explain black holes?',app.policy).is_empty(),'General intelligence remains with conversation model')
 check(app.messages.size()==original and app.desktop_actions.last_result==calls,'Capability descriptions cause no effects or history writes')
 for example in ['запомни: купить хлеб','remember: buy bread','记住：买面包']:
  check(app.router.route(example).get('tool')=='notes.add','Capability example is an executable supported command')
 print('CAPABILITY017_TESTS: %d checks, %d failures; actual registry/self-knowledge,3locales,20repetitions each' %[checks,failures])
 quit(0 if failures==0 else 1)
