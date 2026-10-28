extends SceneTree
var checks=0
var failures=0
class Capture extends Node:
 func submit(_messages,_options):return true
 func cancel():pass
class Runtime extends 'res://src/runtime/local_runtime.gd':
 func installed():return true
 func touch():pass
 func stop():pass
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func frame():
 await process_frame;await process_frame
 RenderingServer.force_draw.call_deferred();await RenderingServer.frame_post_draw
func run():
 if DisplayServer.get_name()=='headless':quit(1);return
 var app=root.get_node('App');app.cancel();var boot=load('res://scenes/bootstrap.tscn').instantiate();root.add_child(boot);await create_timer(1.2).timeout
 var old=[app.provider,app.local_runtime,app.provider_name,app.local_ai_enabled]
 var provider=Capture.new();var runtime=Runtime.new();app.add_child(provider);app.add_child(runtime);runtime.status='ai_ready'
 app.provider=provider;app.local_runtime=runtime;app.provider_name='local_worker';app.local_ai_enabled=true;app.application_access.target={};app.store.data.settings['experimental_logic_formalization']=true
 app.show_chat();await create_timer(.3).timeout;var view=app.chat_window.view
 var question='Все большие роботы устройства. Некоторые устройства красные. Следует ли, что некоторые большие роботы красные?'
 var proposal={'premises':[{'kind':'all','subject':'большие роботы','predicate':'устройства','quote':'Все большие роботы устройства.'},{'kind':'some','subject':'устройства','predicate':'красные','quote':'Некоторые устройства красные.'}],'conclusion':{'kind':'some','subject':'большие роботы','predicate':'красные'}}
 for locale in ['ru','en','zh-Hans']:
  app.cancel();app.set_locale(locale);app.submit(question);await frame()
  check(view.status_label.text.begins_with(app.t('logic_interpreting')) and not view.stop_button.disabled,'Native optional interpreter stage '+locale)
  for size in [Vector2i(320,280),Vector2i(360,320),Vector2i(460,460)]:
   app.chat_window.size=size;await frame();var bounds=Rect2(Vector2.ZERO,Vector2(size))
   check(bounds.encloses(view.editor.get_global_rect()),'Input accessible '+locale+str(size))
   check(bounds.encloses(view.stop_button.get_global_rect()),'Stop accessible '+locale+str(size))
  app._on_answer(JSON.stringify(proposal));await frame()
  check('большие роботы' in view.history.get_parsed_text() and not '"premises"' in view.history.get_parsed_text(),'Interpretation displayed as human text '+locale)
  var target={'handle':'123','target_pid':234,'started':'345','title':'Synthetic long source title','app':'Unknown'}
  app.application_access.target=target;app.window_read_target=target;app.window_read_mode='thinking';app.window_read_context=app.window_reader.prepare('budget',target,[{'kind':'text','text':'Budget42.'}],Time.get_ticks_msec(),locale);app.state.transition('thinking');app._on_answer('{bad JSON}');await frame()
  check(app.t('window_read_unverified') in view.history.get_parsed_text() and 'Budget42.' in view.history.get_parsed_text(),'Original evidence fallback visible '+locale)
  app.application_access.target={}
 app.cancel();app.store.data.settings.erase('experimental_logic_formalization');app.provider=old[0];app.local_runtime=old[1];app.provider_name=old[2];app.local_ai_enabled=old[3];provider.queue_free();runtime.queue_free()
 print('LOGIC_VISUAL021: %d checks, %d failures; nativeX11syntheticdata,notWindows' %[checks,failures]);quit(0 if failures==0 else 1)
