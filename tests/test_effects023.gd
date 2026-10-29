extends SceneTree
var checks=0
var failures=0
class Access extends 'res://src/tools/application_access.gd':
 var requests=[]
 func _request(payload):operation=payload.operation;requests.append(payload.duplicate(true));return true
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func target():return {'handle':'123','target_pid':234,'started':'345','title':'Unbranded third-party client','app':'Client'}
func nodes(on=false):return [{'id':'1,1','name':'Tunnel mode','type':'ControlType.CheckBox','automation_id':'tunnel','ancestors':[],'enabled':true,'toggle':true,'toggle_state':1 if on else 0}]
func observe(access,items):access._finish({'status':'inspected','title':target().title,'nodes':items,'partial':false})
func run():
 var app=root.get_node('App');app.cancel();var original=app.application_access
 var access=Access.new();app.add_child(access);app.application_access=access;access.target=target()
 access.snapshot_ready.connect(app._goal_observed);access.completed.connect(app._goal_access_completed)
 var plan={'ok':true,'action':'enable','node':nodes()[0],'text':'','append':false,'target':target(),'at':Time.get_ticks_msec()}
 app.goal_plan=plan;app.goal_origin_target=target();app.goal_mode='proposal';app.goal_deadline_ms=Time.get_ticks_msec()+30000
 check(app.confirm_window_goal(),'Stateful action requires review')
 observe(access,nodes())
 check(access.requests[-1].pattern=='enable' and access.requests[-1].expected_toggle_state==0,'Fresh observed toggle state carried into native effect')
 access._finish({'status':'toggle_set'})
 check(app.goal_mode=='verifying','Native acknowledgement still needs a fresh observation')
 observe(access,nodes(true))
 check(app.goal_mode.is_empty() and app.messages[-1].text.contains(app.t('goal_verified_enable',{'name':'Tunnel mode'})),'Confirmed ON state is reported without connection claim')
 app.cancel();access.target=target();access.nodes=nodes(true)
 check(not access.act_id(plan,true),'Changed toggle state invalidates stale plan')
 # Invoke result is observed UI change, never final goal completion.
 app.agent.begin('enable network access',target(),Time.get_ticks_msec())
 var button={'id':'2,1','name':'Start','type':'ControlType.Button','automation_id':'start','ancestors':[],'enabled':true,'invoke':true}
 app.goal_plan=plan.merged({'action':'invoke','node':button},true);app.goal_origin_target=target();app.goal_mode='proposal';app.goal_deadline_ms=Time.get_ticks_msec()+30000
 check(app.confirm_window_goal(),'Generic delegated invoke still requires review')
 observe(access,[button]);var effects=access.requests.filter(func(p):return p.operation=='invoke').size()
 access._finish({'status':'invoked'})
 check(app.goal_mode=='verifying','Invoke does not immediately stop as completed')
 var updated=button.duplicate(true);updated.name='Stop';observe(access,[updated])
 check(app.agent.history.size()==1 and app.agent.history[0].result=='ui_changed_not_goal_verified','Observed transition receipt cannot masquerade as verified goal')
 check(app.goal_mode=='between' and app.messages[-1].text==app.t('goal_observed_invoke',{'name':'Start','window':target().title}),'Shared loop continues with honest UI-only receipt')
 check(access.requests.filter(func(p):return p.operation=='invoke').size()==effects,'Verification never repeats effect')
 app.cancel();await create_timer(.4).timeout
 check(not app.agent.active and app.goal_mode.is_empty(),'Cancel revokes scheduled continuation')
 access.target=target();app.agent.begin('enable network access',target(),Time.get_ticks_msec())
 for i in range(2):
  app.goal_mode='executing';app.goal_origin_target=target();app.state.reset();app.state.transition('executing')
  app._goal_access_completed({'status':'stale'})
  check(app.agent.active and app.agent.recovery_attempts==i+1 and app.goal_mode=='observing','Stale element re-observed before a new proposal')
 app.goal_mode='executing';app._goal_access_completed({'status':'stale'})
 check(not app.agent.active and app.goal_mode.is_empty(),'Stale recovery budget stops repeated instability')
 app.cancel();app.application_access=original;access.queue_free()
 print('EFFECTS023: %d checks, %d failures; injected UIA transitions, not Windows/network verification' %[checks,failures]);quit(0 if failures==0 else 1)
