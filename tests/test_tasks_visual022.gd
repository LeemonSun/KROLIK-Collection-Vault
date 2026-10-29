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
  app.browser_tabs.query='SoundCloud';app.browser_tabs.matches({'tabs':[{'identity':{'app':'opera'},'node':{'name':'SoundCloud · Synthetic profile A'}},{'identity':{'app':'chrome'},'node':{'name':'SoundCloud · Synthetic profile B'}}]});app.changed.emit()
  for size in [Vector2i(320,280),Vector2i(360,320),Vector2i(460,560)]:
   app.chat_window.size=size;await frame();var bounds=Rect2(Vector2.ZERO,Vector2(size))
   check(view.task_card.visible and view.tab_choices.item_count==2,'Real choice card '+locale+str(size))
   check(bounds.encloses(view.editor.get_global_rect()),'Input accessible '+locale+str(size))
   check(bounds.encloses(view.stop_button.get_global_rect()),'Stop accessible '+locale+str(size))
   check(bounds.encloses(view.tab_open.get_global_rect()),'Choose accessible '+locale+str(size))
  if locale=='ru':
   var output=OS.get_environment('COMPANION_VISUAL_OUTPUT')
   if not output.is_empty():view.get_viewport().get_texture().get_image().save_png(output.path_join('tasks022.png'))
  app.cancel();app.changed.emit();await frame();check(not view.task_card.visible,'Cancel hides transient choices '+locale)
 print('TASKS_VISUAL022: %d checks, %d failures; synthetic data on native X11, not Windows' %[checks,failures]);quit(0 if failures==0 else 1)
