extends SceneTree
const Component=preload("res://src/ui/component_card.gd")
const Presentation=preload("res://src/core/orbit_presentation.gd")
var checks=0
var failures=0
class Transcriber extends Node:
	var cpu_thread_limit=1
class Speech extends Node:
	var state="idle"
	var transcriber=Transcriber.new()
	func _init():add_child(transcriber)
	func installed():return true
	func busy():return state!="idle"
	func start(_locale):state="recording";return true
	func finish():state="preparing"
	func cancel():state="idle"
func _initialize():run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func identity():return {"handle":"123","target_pid":234,"started":"345","title":"Synthetic third-party app","app":"Client"}
func run():
	var app=root.get_node("App");app.cancel();app.set_locale("ru")
	check(Presentation.snapshot(app).is_empty(),"Idle app has no fabricated task")
	app.goal_mode="observing"
	var state=Presentation.snapshot(app)
	check(state.kind=="observe" and not state.has("percent"),"Task status is observed stage without invented percentage")
	app.goal_mode="proposal";app.goal_deadline_ms=Time.get_ticks_msec()+30000
	app.goal_plan={"ok":true,"target":identity(),"action":"write","node":{"name":"Message"},"text":"Only a preview, not sent","append":false,"generated":true}
	state=Presentation.snapshot(app)
	check(state.kind=="review" and state.detail.contains(app.goal_plan.text),"Complete draft in review card")
	check(Presentation.review_live(app,state.token),"Fresh exact review token allowed")
	app.goal_plan.text="replaced"
	check(not Presentation.review_live(app,state.token),"Old visible review cannot approve a replaced draft")
	state=Presentation.snapshot(app);app.paused=true
	check(not Presentation.review_live(app,state.token),"Pause revokes review")
	app.paused=false;app.goal_deadline_ms=Time.get_ticks_msec()-1
	check(not Presentation.review_live(app,state.token),"Expired card cannot act")
	app.cancel();app.discovery_candidates=[{"name":"Unknown app","id":"a"}]
	state=Presentation.snapshot(app)
	check(state.kind=="choice" and Presentation.choice_live(app,state.token),"Observed app choices available without invented executable paths")
	app.discovery_candidates=[{"name":"Other app","id":"b"}]
	check(not Presentation.choice_live(app,state.token),"Stale application chooser rejected")
	app.cancel()
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	check(main._pages()==["assistant_tools","character","settings"],"Only three normal settings sections")
	app.store.data.settings["advanced_controls"]=true
	check(main._pages().size()==3,"Old developer preference cannot restore technical tabs")
	for locale in ["ru","en","zh-Hans"]:
		app.set_locale(locale);main.page="assistant_tools";main._build();await process_frame
		var count=0
		for child in main.content.get_children():
			if child is Component:
				count+=1;child.refresh();check(child.action.text!=locale and not child.action.text.is_empty(),"Real component installer label "+locale)
		check(count==3,"Conversation/voice/screen cards "+locale)
		check(main.start_ai_button==null and main.stop_ai_button==null,"No manual worker controls "+locale)
	var card=Component.new();card.kind="text";root.add_child(card)
	var managed=app.local_runtime.bundle_managed;var verified=app.local_runtime.bundled_verified
	app.local_runtime.bundle_managed=true;app.local_runtime.bundled_verified=false;card.refresh()
	check(card.action.disabled and card.status.text==app.t("orbit_checking"),"Bundled verification is not presented as an unavailable Download action")
	app.local_runtime.bundle_managed=managed;app.local_runtime.bundled_verified=verified;card.queue_free()
	for path in ["res://legal/README.md","res://legal/upstream/Qwen3.5-2B-LICENSE.txt","res://legal/upstream/NotoCJK-LICENSE.txt"]:
		check(FileAccess.file_exists(path) and not FileAccess.get_file_as_string(path).is_empty(),"Mandatory notices accessible to About: "+path)
	main.queue_free();await process_frame
	app.set_locale("ru");app.cancel()
	var original=app.speech_input;var speech=Speech.new();app.add_child(speech);app.speech_input=speech
	var editor=TextEdit.new();root.add_child(editor)
	check(app.begin_dictation(editor,true) and app.dictation_submit,"Explicit voice conversation arms one submission")
	speech.state="idle";var before=app.messages.size();app._dictation_ready("2+2")
	check(app.messages.size()>=before+2 and app.messages[before].text=="2+2" and editor.text.is_empty(),"Recognized request actually reaches the router, without a Send click")
	app.cancel();editor.text="Keep my draft. "
	check(app.begin_dictation(editor,true) and not app.dictation_submit,"Existing draft prevents silent submission")
	speech.state="idle";before=app.messages.size();app._dictation_ready("more text")
	check(app.messages.size()==before and editor.text.contains("Keep my draft.") and editor.text.contains("more text"),"Voice appends to draft without sending it")
	editor.clear();app.cancel();app.begin_dictation(editor,true);app.cancel();before=app.messages.size();app._dictation_ready("2+2")
	check(app.messages.size()==before and editor.text.is_empty(),"Cancelled dictation cannot submit a late transcript")
	app.speech_input=original;speech.queue_free();editor.queue_free();app.cancel()
	var theme=preload("res://src/ui/visual_theme.gd");var button=Button.new();theme.primary(button)
	check(button.get_theme_stylebox("normal").bg_color==theme.RED and button.get_theme_color("font_color")==theme.INK,"Amber action has dark readable text")
	button.free()
	var rig=preload("res://src/animation/leemon_rig.gd")
	for clip in ["adjust_glasses","peek","offer","listen_confirm"]:check(clip in rig.CLIPS,"Authored shared-master gesture: "+clip)
	print("ORBIT026: %d checks, %d failures; synthetic state/voice routing, not Windows/microphone acceptance" %[checks,failures]);quit(0 if failures==0 else 1)
