extends SceneTree
var checks=0
var failures=0
class Access extends 'res://src/tools/application_access.gd':
 func inspect(_silent=false):return true
class Runtime extends 'res://src/runtime/local_runtime.gd':
 func installed():return true
 func stop():pass
 func touch():pass
class Provider extends Node:
 func submit(_messages,_options):return true
 func cancel():pass
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func frame():
 await process_frame;await process_frame
 RenderingServer.force_draw.call_deferred();await RenderingServer.frame_post_draw
func run():
 if DisplayServer.get_name()=='headless':quit(1);return
 var app=root.get_node('App');app.cancel();root.add_child(load('res://scenes/bootstrap.tscn').instantiate());await create_timer(1.2).timeout
 var old=[app.application_access,app.local_runtime,app.provider,app.provider_name]
 var access=Access.new();var runtime=Runtime.new();var provider=Provider.new()
 for node in [access,runtime,provider]:app.add_child(node)
 runtime.status='ai_ready';app.application_access=access;app.local_runtime=runtime;app.provider=provider;app.provider_name='local_worker'
 app.show_chat();await create_timer(.2).timeout;var view=app.chat_window.view
 for locale in ['ru','en']:
  app.cancel();app.set_locale(locale);access.target={'handle':'123','target_pid':234,'started':'345','title':'Synthetic third-party app','app':'Client'}
  app.begin_agent('Enable a network connection');access.nodes=[]
  for i in range(70):access.nodes.append({'id':'1,'+str(i+1),'name':'Control '+str(i),'type':'ControlType.Button','automation_id':'control'+str(i),'ancestors':[],'enabled':true,'invoke':true})
  access.observed_ms=Time.get_ticks_msec();app._goal_observed();await frame()
  check(view.status_label.text.contains(app.t('goal_scan_pages',{'page':1,'total':app.goal_scan.pages.size()})),'Page progress visible '+locale)
  app._on_answer('{"choice":"none"}');await frame()
  check(app.goal_scan.index==1 and view.status_label.text.contains(app.t('goal_scan_pages',{'page':2,'total':app.goal_scan.pages.size()})),'Next page progress visible '+locale)
  for size in [Vector2i(320,280),Vector2i(360,320),Vector2i(460,560)]:
   app.chat_window.size=size;await frame();var bounds=Rect2(Vector2.ZERO,Vector2(size))
   check(bounds.encloses(view.editor.get_global_rect()),'Input accessible '+locale+str(size))
   check(bounds.encloses(view.stop_button.get_global_rect()) and not view.stop_button.disabled,'Stop accessible '+locale+str(size))
  check(not JSON.stringify(app.diagnostics.last_observation).contains('Control '),'Observation telemetry has no control labels '+locale)
  app.cancel();await frame();check(not app.goal_scan.active and view.stop_button.disabled,'Cancel clears paged task '+locale)
 app.application_access=old[0];app.local_runtime=old[1];app.provider=old[2];app.provider_name=old[3]
 for node in [access,runtime,provider]:node.queue_free()
 print('OBSERVATION_VISUAL024: %d checks, %d failures; RU/EN synthetic native X11, not Windows' %[checks,failures]);quit(0 if failures==0 else 1)
