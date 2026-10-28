extends SceneTree
var checks=0
var failures=0
class Capture extends Node:
 var calls=[]
 func submit(messages,options):calls.append({'messages':messages,'options':options});return true
 func cancel():pass
class Runtime extends "res://src/runtime/local_runtime.gd":
 func _init():status='ai_ready'
 func installed():return true
 func touch():pass
 func stop():pass
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func frame():
 await process_frame
 await process_frame
 RenderingServer.force_draw.call_deferred()
 await RenderingServer.frame_post_draw
func run():
 if DisplayServer.get_name()=='headless':quit(1);return
 var app=root.get_node('App');app.cancel()
 var boot=load('res://scenes/bootstrap.tscn').instantiate();root.add_child(boot)
 await create_timer(1.2).timeout
 var original=[app.provider,app.local_runtime,app.provider_name,app.local_ai_enabled]
 var provider=Capture.new();var runtime=Runtime.new();app.add_child(provider);app.add_child(runtime)
 app.provider=provider;app.local_runtime=runtime;app.provider_name='local_worker';app.local_ai_enabled=true;app.application_access.target={};runtime.status='ai_ready'
 app.show_chat();await create_timer(0.3).timeout;var view=app.chat_window.view
 var examples={'ru':['Составь короткое приглашение на встречу завтра.','Приглашаю на встречу завтра.'],'en':['Compose a short invitation tomorrow.','You are invited to a meeting tomorrow.'],'zh-Hans':['请写一句邀请明天参加会议的话。','诚邀您参加明天的会议。']}
 for locale in examples:
  app.cancel();app.session_turns=[];app.set_locale(locale);app.submit(examples[locale][0]);app._on_answer('Tomorrow at 3 PM.');await frame()
  check(view.status_label.text.begins_with(app.t('chat_draft_repairing')),'Native repair status '+locale)
  check(not view.stop_button.disabled,'Stop remains enabled during correction '+locale)
  for dimensions in [Vector2i(320,280),Vector2i(360,320),Vector2i(460,460)]:
   app.chat_window.size=dimensions;await frame();var bounds=Rect2(Vector2.ZERO,Vector2(dimensions))
   check(bounds.encloses(view.editor.get_global_rect()),'Input remains visible '+locale+str(dimensions))
   check(bounds.encloses(view.stop_button.get_global_rect()),'Stop remains visible '+locale+str(dimensions))
  app._on_answer(examples[locale][1]);await frame()
  check(app.t('chat_draft_heading') in view.history.get_parsed_text(),'Native delivered draft label '+locale)
  check(not app.messages.any(func(m):return m.text=='Tomorrow at 3 PM.'),'Rejected content absent from visible chat '+locale)
 app.cancel();app.provider=original[0];app.local_runtime=original[1];app.provider_name=original[2];app.local_ai_enabled=original[3];provider.queue_free();runtime.queue_free()
 print('CHAT_DRAFT_VISUAL020: %d checks, %d failures; native X11, fake generation, not model quality' %[checks,failures])
 quit(0 if failures==0 else 1)
