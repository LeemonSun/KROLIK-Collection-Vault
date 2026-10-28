extends SceneTree
const Access=preload('res://src/tools/application_access.gd')
var checks=0
var failures=0
class FakeAccess extends Access:
 var requests=[]
 func _request(payload):operation=payload.operation;requests.append(payload.duplicate(true));return true
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func frame():
 await process_frame
 await process_frame
 RenderingServer.force_draw.call_deferred()
 await RenderingServer.frame_post_draw
func control(selected=false,id='1,1'):return {'id':id,'name':'Options','type':'ControlType.TabItem','automation_id':'options','ancestors':[{'name':'Synthetic application','type':'ControlType.Window','automation_id':'root'},{'name':'Long section with more context / Длинное название раздела / 设置','type':'ControlType.Pane','automation_id':'settings'},{'name':'Editor / Редактор / 编辑器','type':'ControlType.Group','automation_id':'editor'}],'enabled':true,'select':true,'selected':selected}
func observe(access,selected=false,id='1,1'):
 access._finish({'status':'inspected','title':'Synthetic app','nodes':[control(selected,id)],'partial':true})
func run():
 if DisplayServer.get_name()=='headless':quit(1);return
 var app=root.get_node('App');app.cancel()
 var boot=load('res://scenes/bootstrap.tscn').instantiate();root.add_child(boot)
 await create_timer(1.2).timeout
 var original=app.application_access
 var access=FakeAccess.new();app.add_child(access);access.target={'handle':'123','target_pid':234,'started':'345','title':'Synthetic app','app':'Unknown'}
 access.snapshot_ready.connect(app._goal_observed);access.completed.connect(app._goal_access_completed);access.changed.connect(app._access_changed)
 app.application_access=access;app.show_chat();await create_timer(0.3).timeout
 var view=app.chat_window.view
 for locale in ['ru','en','zh-Hans']:
  app.set_locale(locale);app.begin_window_goal('select Options');observe(access);await frame()
  check('Editor / Редактор / 编辑器' in view.history.get_parsed_text(),'Observed section appears in native review '+locale)
  check(app.messages[-1].get('ephemeral',false),'Window review is ephemeral '+locale)
  for dimensions in [Vector2i(320,280),Vector2i(360,320),Vector2i(460,460)]:
   app.chat_window.size=dimensions;await frame()
   var bounds=Rect2(Vector2.ZERO,Vector2(dimensions))
   check(bounds.encloses(view.editor.get_global_rect()),'Input reachable with long section '+locale+str(dimensions))
   check(view.confirmation_button.visible and bounds.encloses(view.confirmation_button.get_global_rect()),'Approval reachable with long section '+locale+str(dimensions))
  app.confirm_window_goal();observe(access);access._finish({'status':'selected'});observe(access);await frame()
  check(app.goal_mode=='verify_wait' and view.status_label.text==app.t('goal_status_verify_wait'),'Native asynchronous verification status '+locale)
  await create_timer(0.35).timeout;observe(access,true,'1,2');await frame()
  check(app.goal_mode.is_empty() and app.messages[-1].text==app.t('goal_verified_select',{'name':'Options'}),'Verified outcome shown after fresh state '+locale)
  root.get_texture().get_image() # Actual character viewport remains accessible.
 app.cancel();app.application_access=original;access.queue_free()
 print('AGENT_VISUAL019: %d checks, %d failures; real X11 layout, synthetic UIA, not Windows' %[checks,failures])
 quit(0 if failures==0 else 1)
