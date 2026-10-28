extends SceneTree
const Controls=preload("res://src/core/control_context.gd")
const Agent=preload("res://src/core/adaptive_agent.gd")
const Planner=preload("res://src/core/action_proposal.gd")
const Access=preload("res://src/tools/application_access.gd")
var checks=0
var failures=0
class FakeAccess extends Access:
 var requests=[]
 func _request(payload):requests.append(payload.duplicate(true));return true
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func identity():return {"handle":"123","target_pid":234,"started":"345","title":"Synthetic app","app":"Unknown app"}
func control(id,section):return {"id":id,"name":"Options","type":"ControlType.TabItem","automation_id":"options","ancestors":[{"name":section,"type":"ControlType.Pane","automation_id":section.to_lower()}],"enabled":true,"select":true,"selected":false}
func run():
 var first=control('1,1','Editor');var second=control('1,2','Player');var recreated=first.duplicate(true);recreated.id='1,3'
 check(Controls.exact(first,first) and not Controls.exact(first,recreated),'Exact binding requires the current runtime ID')
 check(not Controls.same(first,second),'Same label and AutomationId in different containers are different controls')
 check(Controls.stable(first,recreated),'Stable contextual match available for outcome observation')
 check(Controls.resolve(first,[recreated]).is_empty(),'No implicit action retargeting after recreation')
 check(Controls.resolve(first,[recreated],true).id=='1,3','Unique contextual recreation can verify an outcome')
 var duplicate=recreated.duplicate(true);duplicate.id='1,4'
 check(Controls.resolve(first,[recreated,duplicate],true).is_empty(),'Ambiguous stable context cannot verify a different control')
 var reused=second.duplicate(true);reused.id=first.id
 check(Controls.resolve(first,[reused,recreated],true).is_empty(),'Reused runtime ID with changed scope blocks fallback')
 var incomplete=first.duplicate(true);incomplete.automation_id=''
 check(not Controls.stable(incomplete,incomplete),'Name plus container alone cannot reidentify')
 var no_parent=first.duplicate(true);no_parent.ancestors=[]
 check(not Controls.stable(no_parent,no_parent),'AutomationId alone is not treated as globally unique')
 var large=first.duplicate(true);large.ancestors=[]
 for i in range(10):large.ancestors.append({'name':'x'.repeat(200),'type':'y'.repeat(90),'automation_id':'z'.repeat(100)})
 var bounded=Controls.descriptor(large)
 check(bounded.ancestors.size()==3 and bounded.ancestors[0].name.length()==64 and bounded.ancestors[0].automation_id.length()==64,'Context is bounded before native requests or prompts')
 for locale in ['ru','en','zh-Hans']:
  var agent=Agent.new();var now=Time.get_ticks_msec();agent.begin('Find Options in Editor',identity(),now)
  var ctx=agent.prepare(identity(),[second,first],now,now,locale,{'partial':true})
  var payload=JSON.parse_string(ctx.messages[1].content)
  check(payload.controls[0].container==['Editor'] and payload.observation_partial,'Container context ranks the relevant section '+locale)
  check(not payload.controls[0].has('automation_id'),'Opaque native identifier is not sent as meaning '+locale)
  var plan=agent.validate(JSON.stringify({'choice':'select:e0'}),ctx,identity(),now)
  check(plan.ok and agent.record(plan,true,identity(),now),'Verified scoped step recorded '+locale)
  ctx=agent.prepare(identity(),[first,second],now,now,locale)
  check(ctx.ok and ctx.map.size()==1 and ctx.map.values()[0].ancestors[0].name=='Player','Completed Editor control does not suppress Player control '+locale)
  payload=JSON.parse_string(ctx.messages[1].content)
  check(payload.verified_steps[0].container==['Editor'],'Step history preserves contextual evidence '+locale)
  agent.clear();check(agent.history.is_empty() and agent.visited_navigation.is_empty(),'Cancel drops private context '+locale)
 var now=Time.get_ticks_msec();var ambiguity_agent=Agent.new();ambiguity_agent.begin('Find Options',identity(),now)
 var original_ctx=ambiguity_agent.prepare(identity(),[first],now,now,'en')
 var original_plan=ambiguity_agent.validate(JSON.stringify({'choice':'select:e0'}),original_ctx,identity(),now)
 ambiguity_agent.record(original_plan,true,identity(),now)
 var duplicate_ctx=ambiguity_agent.prepare(identity(),[first,recreated],now,now,'en')
 check(duplicate_ctx.ok and duplicate_ctx.map.size()==1 and duplicate_ctx.map.values()[0].id=='1,3','Duplicate provider AutomationId cannot suppress a separate current runtime ID')
 check(ambiguity_agent.validate(JSON.stringify({'choice':'select:e0'}),duplicate_ctx,identity(),now).ok,'History validation uses full observation, including filtered completed controls')
 check(not JSON.parse_string(duplicate_ctx.messages[1].content).has('identity_nodes'),'Identity snapshot stays local, outside model prompt')
 var worker=FakeAccess.new();root.add_child(worker);worker.target=identity();worker.nodes=[first];worker.observed_ms=Time.get_ticks_msec()
 var plan={'ok':true,'action':'select','node':first,'target':identity(),'text':'','append':false}
 check(worker.act_id(plan,true) and worker.requests[-1].element_descriptor.ancestors[0].name=='Editor','Effect request binds observed scope and type')
 var count=worker.requests.size();worker.nodes=[reused]
 check(not worker.act_id(plan,true) and worker.requests.size()==count,'Same ID/name with a changed container cannot consume approval')
 worker.nodes=[recreated]
 check(not worker.act_id(plan,true) and worker.requests.size()==count,'Stable reidentification cannot execute an approved old action')
 worker.nodes=[first,first]
 check(not worker.act_id(plan,true),'Duplicate exact identities cannot execute')
 worker._result({'status':'inspected','nodes':[first],'partial':true,'visited':200,'elapsed_ms':2501})
 check(worker.observation.partial and worker.observation.visited==200 and worker.observation.elapsed_ms==2501,'Inspection exposes bounded partial-observation metadata')
 check(not worker.last_result.has('nodes') and not worker.last_result.has('title'),'Completion receipt does not duplicate private control labels')
 worker.clear_target();check(worker.observation.is_empty() and worker.last_result.is_empty(),'Clearing target clears observation metadata and receipt')
 worker.queue_free()
 print('CONTROL_CONTEXT019: %d checks, %d failures; synthetic generic controls, not real Windows' %[checks,failures])
 quit(0 if failures==0 else 1)
