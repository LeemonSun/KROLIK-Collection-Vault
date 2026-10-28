extends SceneTree
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func frame():
 await process_frame;await process_frame
 RenderingServer.force_draw.call_deferred();await RenderingServer.frame_post_draw
func run():
 var app=root.get_node('App');var boot=load('res://scenes/bootstrap.tscn').instantiate();root.add_child(boot)
 await create_timer(.4).timeout;app.show_chat();await frame()
 var original=app.provider;var fake=preload('res://tests/test_adaptive015.gd').FakeProvider.new();app.add_child(fake);app.provider=fake
 var view=app.chat_window.view
 for locale in ['ru','en','zh-Hans']:
  app.cancel();app.set_locale(locale)
  var target={'handle':'12','target_pid':34,'started':'56','title':'Synthetic editor','app':'editor'};app.application_access.target=target
  app.agent.begin('Compose a short greeting in Body',target,Time.get_ticks_msec())
  app.goal_context=app.agent.prepare(target,[{'id':'1','name':'Body','type':'ControlType.Edit','enabled':true,'write':true}],Time.get_ticks_msec(),Time.get_ticks_msec(),locale)
  app._start_goal_composition('e0');await frame()
  check(app.goal_mode=='composing' and app.t('goal_status_composing') in view.status_label.text,'Actual composing stage visible '+locale)
  for dimensions in [Vector2i(320,280),Vector2i(460,560)]:
   app.chat_window.size=dimensions;await frame()
   var bounds=Rect2(Vector2.ZERO,Vector2(dimensions))
   check(bounds.encloses(view.editor.get_global_rect()) and bounds.encloses(view.stop_button.get_global_rect()),'Input/stop fit during composition '+locale+str(dimensions))
   check(not view.stop_button.disabled and view.plan_button.disabled,'Stop available and competing plan disabled '+locale)
  app._on_answer('Welcome, everyone!');await frame()
  check(app.goal_mode=='proposal' and view.confirmation_button.visible and 'Welcome, everyone!' in view.history.get_parsed_text(),'Complete draft approval appears after composing '+locale)
  check(app.application_access.pid<0,'Preview causes no native process '+locale)
  app.cancel();await frame();check(not view.confirmation_button.visible,'Stop revokes visible proposal '+locale)
 app.provider=original;fake.queue_free()
 print('COMPOSER_VISUAL017_TESTS: %d checks, %d failures; actual X11 stage/layout, synthetic inference and UIA' %[checks,failures])
 quit(0 if failures==0 else 1)
