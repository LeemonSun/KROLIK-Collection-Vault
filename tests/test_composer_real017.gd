extends SceneTree
var checks=0
var failures=0
var raw_draft=""
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func run():
 var app=root.get_node('App');app.cancel()
 var fixture=preload('res://tests/test_adaptive015.gd');var access=fixture.FakeAccess.new();app.add_child(access)
 access.snapshot_ready.connect(app._goal_observed);access.completed.connect(app._goal_access_completed);access.changed.connect(app._access_changed)
 app.application_access=access;var runtime=fixture.FakeRuntime.new();app.add_child(runtime);app.local_runtime=runtime
 app._set_provider('local_worker');app.provider.configure_local(int(OS.get_environment('COMPANION_TEST_PORT')),OS.get_environment('COMPANION_TEST_TOKEN'));app.provider.completed.connect(func(text):raw_draft=text)
 for spec in [['ru','Составь в поле Body короткое приглашение на встречу завтра, одним предложением.'],['en','Compose a one-sentence invitation for a meeting tomorrow in Body.'],['zh-Hans','请写一句邀请明天参加会议的话，填入Body。']]:
  app.set_locale(spec[0]);access.target={'handle':'123','target_pid':234,'started':'345','title':'Synthetic editor','app':'editor'}
  check(app.begin_agent(spec[1]),'Explicit goal starts '+spec[0])
  access._finish({'status':'inspected','title':'Synthetic editor','nodes':[{'id':'10','name':'Body','type':'ControlType.Edit','enabled':true,'write':true}]})
  check(app.goal_mode=='composing','Unique writable field directly enters authoring, not action JSON '+spec[0])
  var deadline=Time.get_ticks_msec()+100000
  while app.goal_mode=='composing' and Time.get_ticks_msec()<deadline:await process_frame
  var text=str(app.goal_plan.get('text',''));var relevant=false
  for word in ['встреч','встрет','meeting','会议']:if word in text.to_lower():relevant=true
  check(app.goal_mode=='proposal' and relevant,'Actual app receives a relevant composed proposal '+spec[0])
  check(not '2 PM' in text and not 'я встретимся' in text.to_lower() and not 'Body' in text,'Observed invented time/malformed phrase absent '+spec[0])
  check(access.requests.size()>=1 and access.requests[-1].operation=='inspect','No native write before approval '+spec[0])
  print('REAL_COMPOSER017 ',JSON.stringify({'locale':spec[0],'goal':spec[1],'mode':app.goal_mode,'draft':text,'raw_draft':raw_draft,'usage':app.provider.last_usage}))
  if app.goal_mode=='proposal':
   app.confirm_window_goal();access._finish({'status':'inspected','title':'Synthetic editor','nodes':[{'id':'10','name':'Body','type':'ControlType.Edit','enabled':true,'write':true}]})
   check(access.requests[-1].operation=='write' and access.requests[-1].text==text,'Reviewed text reaches synthetic native bridge after preflight '+spec[0])
  app.cancel()
 print('COMPOSER_REAL017_TESTS: %d checks, %d failures; real pinned2B and App, synthetic Windows UIA only' %[checks,failures])
 quit(0 if failures==0 else 1)
