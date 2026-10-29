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
 if DisplayServer.get_name()=='headless':quit(1);return
 var app=root.get_node('App');app.cancel();root.add_child(load('res://scenes/bootstrap.tscn').instantiate());await create_timer(1.2).timeout
 app.show_chat();await create_timer(.3).timeout;var view=app.chat_window.view
 for locale in ['ru','en','zh-Hans']:
  app.cancel();app.set_locale(locale)
  app.discovery_candidates=[{'name':'Synthetic third-party client A','product':'Network client'},{'name':'Synthetic third-party client B','product':'Portable app'}];app.discovery_at=Time.get_ticks_msec();app.changed.emit()
  for size in [Vector2i(320,280),Vector2i(360,320),Vector2i(460,560)]:
   app.chat_window.size=size;await frame();var bounds=Rect2(Vector2.ZERO,Vector2(size))
   check(view.task_card.visible and view.tab_choices.item_count==2,'Application choice card '+locale+str(size))
   check(bounds.encloses(view.editor.get_global_rect()),'Input accessible '+locale+str(size))
   check(bounds.encloses(view.stop_button.get_global_rect()) and not view.stop_button.disabled,'Cancel choice accessible '+locale+str(size))
   check(bounds.encloses(view.tab_open.get_global_rect()),'Choose app accessible '+locale+str(size))
  app.discovery_candidates=[];app.discovery_mode='thinking';app.discovery_deadline=Time.get_ticks_msec()+120000;app.state.transition('thinking');app.changed.emit();await frame()
  check(view.task_card.visible and view.task_label.text==app.t('discover_thinking') and not view.tab_row.visible,'Semantic discovery stage visible '+locale)
  app.cancel();app.changed.emit();await frame();check(not view.task_card.visible,'Stop clears all discovery UI '+locale)
 print('DISCOVERY_VISUAL023: %d checks, %d failures; synthetic native X11, not Windows' %[checks,failures]);quit(0 if failures==0 else 1)
