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
func identity():return {'handle':'123','target_pid':234,'started':'345','title':'Synthetic editor','app':'Unknown app'}
func control(selected=false,id='1,1'):return {'id':id,'name':'Options','type':'ControlType.TabItem','automation_id':'options','ancestors':[{'name':'Editor','type':'ControlType.Pane','automation_id':'editor'}],'enabled':true,'select':true,'selected':selected}
func observe(access,selected=false,id='1,1'):
 access._finish({'status':'inspected','title':'Synthetic editor','nodes':[control(selected,id)],'partial':true})
func prepare(app,access):
 check(app.begin_window_goal('select Options'),'Explicit supported task starts')
 observe(access)
 check(app.goal_mode=='proposal','Literal unique selection gets a review')
 check('Editor' in app.messages[-1].text and app.messages[-1].get('ephemeral',false),'Review includes parent section and stays out of saved history')
 app.confirm_window_goal();observe(access)
 check(access.requests[-1].pattern=='select' and access.requests[-1].element_descriptor.automation_id=='options','Fresh scoped preflight precedes a single effect')
 access._finish({'status':'selected'})
 check(app.goal_mode=='verifying','Action acknowledgement is not proof of selected state')
func run():
 var app=root.get_node('App');app.cancel();app.set_locale('en')
 var old_access=app.application_access
 var access=FakeAccess.new();app.add_child(access);access.target=identity()
 access.snapshot_ready.connect(app._goal_observed);access.completed.connect(app._goal_access_completed);access.changed.connect(app._access_changed)
 app.application_access=access
 var before_turns=app.session_turns.duplicate(true)
 prepare(app,access);observe(access)
 check(app.goal_mode=='verify_wait' and app.goal_verify_attempt==1,'Unchanged first observation waits for asynchronous UI state')
 var effects=access.requests.filter(func(r):return r.operation=='invoke').size()
 await create_timer(0.35).timeout
 check(app.goal_mode=='verifying' and app.goal_verify_attempt==2 and access.requests[-1].operation=='inspect','Retry is observation only')
 observe(access,true,'1,2')
 check(app.goal_mode.is_empty() and app.messages[-1].text==app.t('goal_verified_select',{'name':'Options'}),'Unique contextual recreation can verify selected state')
 check(access.requests.filter(func(r):return r.operation=='invoke').size()==effects,'Delayed verification never repeats the click')
 check(app.session_turns==before_turns,'Private window scope does not enter dialogue memory')
 prepare(app,access);observe(access)
 await create_timer(0.35).timeout;observe(access)
 check(app.goal_mode=='verify_wait' and app.goal_verify_attempt==2,'Second unchanged observation gets a final bounded wait')
 await create_timer(0.7).timeout;observe(access)
 check(app.goal_mode.is_empty() and app.messages[-1].text==app.t('goal_unverified'),'Three unchanged observations stop without claiming success')
 prepare(app,access);observe(access)
 app.cancel();var count=access.requests.size();await create_timer(0.35).timeout
 check(access.requests.size()==count and app.goal_mode.is_empty(),'Cancel revokes pending verification timer')
 prepare(app,access);observe(access)
 app.set_paused(true);count=access.requests.size();await create_timer(0.35).timeout
 check(access.requests.size()==count and app.goal_mode.is_empty(),'Pause revokes pending verification timer');app.set_paused(false)
 prepare(app,access);observe(access)
 app.goal_deadline_ms=Time.get_ticks_msec()-1
 app._retry_goal_verification(app.goal_verify_revision)
 check(app.goal_mode.is_empty(),'Overall verification deadline cannot be renewed by a retry')
 app.begin_window_goal('select Options');observe(access);app.confirm_window_goal()
 var changed=control();changed.ancestors[0].name='Another section'
 count=access.requests.filter(func(r):return r.operation=='invoke').size()
 access._finish({'status':'inspected','title':'Synthetic editor','nodes':[changed]})
 check(app.goal_mode.is_empty() and access.requests.filter(func(r):return r.operation=='invoke').size()==count,'Changed container during approval preflight cannot execute')
 app.cancel();app.application_access=old_access;access.queue_free()
 print('VERIFICATION019: %d checks, %d failures; actual App with synthetic UIA, no real Windows' %[checks,failures])
 quit(0 if failures==0 else 1)
