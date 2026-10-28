extends SceneTree
var checks=0
var failures=0
class NoModel extends Node:
 var called=false
 func submit(_messages,_options):called=true;return false
 func cancel():pass
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func run():
 var app=root.get_node('App');app.cancel();var old=[app.provider,app.local_ai_enabled,app.provider_name];var fake=NoModel.new();app.add_child(fake);app.provider=fake;app.local_ai_enabled=false;app.provider_name='unconfigured'
 var path=get_script().resource_path.get_base_dir().path_join('fixtures/logic021-cases.json')
 var cases=JSON.parse_string(FileAccess.get_file_as_string(path));var before=Time.get_ticks_usec()
 for spec in cases:
  app.set_locale(spec.locale);app.submit(spec.input)
  check(not fake.called and app.state.current=='idle' and not app.local_runtime.generation_busy,'No inference/AI install needed '+spec.id)
  var expected={'ru':{'entailed':'вывод следует','undetermined':'вывод не следует','inconsistent':'условия несовместимы'},'en':{'entailed':'conclusion follows','undetermined':'conclusion does not follow','inconsistent':'premises are inconsistent'},'zh-Hans':{'entailed':'结论可以推出','undetermined':'结论无法推出','inconsistent':'前提本身互相矛盾'}}[spec.locale][spec.expected]
  check(expected in app.messages[-1].text,'RealApp delivers verified limited-scope verdict '+spec.id)
 check(app.session_turns.size()<=12,'Local reasoning keeps existing bounded dialogue context')
 print('LOGIC_FAST021: %dchecks,%dfailures;12syntheticrealAppqueries,elapsed_usec=%d;notWindowsnotgeneralIQ' %[checks,failures,Time.get_ticks_usec()-before])
 app.cancel();app.provider=old[0];app.local_ai_enabled=old[1];app.provider_name=old[2];fake.queue_free();quit(0 if failures==0 else 1)
