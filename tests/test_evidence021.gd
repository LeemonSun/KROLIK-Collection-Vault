extends SceneTree
const Reader=preload('res://src/core/window_reader.gd')
const Selection=preload('res://src/core/evidence_selection.gd')
var checks=0
var failures=0
class Capture extends Node:
 var calls=[]
 func submit(messages,options):calls.append({'messages':messages,'options':options});return true
 func cancel():pass
class Runtime extends Node:
 var status='ai_ready'
 var generation_busy=false
 func installed():return true
 func touch():pass
 func stop():pass
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func identity():return {'handle':'123','target_pid':234,'started':'345','title':'Synthetic document','app':'Unknown'}
func answer(text,sources=['r0']):return JSON.stringify({'answer':text,'sources':sources,'insufficient':false})
func run():
 var reader=Reader.new();var target=identity()
 for spec in [['ru','Где находится библиотека?','Библиотека находится на улице Сосновой.'],['en','What is the budget?','The budget is42credits.'],['zh-Hans','预算是多少？','预算是42积分。']]:
  var blocks=[]
  for i in range(45):blocks.append({'kind':'text','text':'Unrelated paragraph '+str(i)+' '+('abcdef '.repeat(45))})
  blocks.append({'kind':'text','text':spec[2]})
  var ctx=reader.prepare(spec[1],target,blocks,1000,spec[0])
  check(ctx.ok and ctx.map.r0==spec[2],'Late observed relevant fragment prioritized '+spec[0])
  check(JSON.stringify(ctx.rows).to_utf8_buffer().size()<=Reader.MAX_BYTES and ctx.rows.size()<=18,'Serialized evidence stays bounded '+spec[0])
  check(reader.fallback(ctx,target,1001)[0]==spec[2],'Fallback uses ranked original data '+spec[0])
 var context=reader.prepare('When is the meeting?',target,[{'kind':'text','text':'The meeting is Friday at14:30. Budget42. Email a@example.org.'},{'kind':'text','text':'Other event Wednesday at09:00. Budget99.'}],1000,'en')
 for text in ['Friday at14:30.','В пятницу в14:30.','星期五14:30。']:
  check(reader.validate(answer(text),context,target,1001).get('ok',false),'Supported literal/day across languages '+text)
 for text in ['Friday at15:30.','Wednesday at14:30.','星期三14:30。','В среду в14:30.','Budget99.','a@invented.org','See https://invented.org','The meeting is tomorrow.','Invite has been sent.']:
  check(not reader.validate(answer(text),context,target,1001).get('ok',false),'Unsupported cited claim rejected '+text)
 check(reader.validate(answer('Other event Wednesday at09:00.',['r1']),context,target,1001).get('ok',false),'Exact other cited source accepted')
 check(not reader.validate(answer('Budget42.',['r1']),context,target,1001).get('ok',false),'Uncited source cannot witness a number')
 check(not Reader.exact_numbers('42%', '42') and not Reader.exact_numbers('-42','42') and not Reader.exact_numbers('42','-42'),'Numeric signs/percentage cannot be invented or discarded')
 check(Reader.exact_numbers('42%', '42%') and Reader.exact_numbers('-42','-42'),'Exact signed/percentage witnesses retained')
 check(reader.validate(answer('The meeting is in the observatory.'),context,target,1001).get('ok',false),'Known nonnumeric hallucination limitation remains explicit')
 for malformed in [null,12,{},[]]:
  check(not reader.prepare('q',target,malformed,1000).ok,'Invalid blocks handled')
 check(not reader.prepare('q',{},[],1000).ok,'Missing identity rejected')
 check(not reader.prepare('q',{'title':'x'},[{'kind':'text','text':'x'}],1000).ok,'Incomplete identity rejected before inference')
 check(not reader.prepare('q',target,[{'kind':'text','text':'x'}],-1).ok,'Invalid timestamp rejected')
 check(reader.fallback(context,target,92000).is_empty(),'Expired evidence not shown on invalid model output')
 var other=target.duplicate();other.title='Different page'
 check(reader.fallback(context,other,1001).is_empty(),'Changed title cannot display prior evidence')
 check(reader.fallback(context,target,999).is_empty(),'Future observation not shown')
 var terms=Selection.terms('资料'.repeat(1000));check(terms.size()<=Selection.MAX_TERMS,'Term work bounded')
 var duplicates=Selection.take('q',[{'kind':'text','text':'Same'},{'kind':'text','text':'same'},null,{'kind':'bad','text':'invalid'}],100)
 check(duplicates.rows.size()==1,'Invalid/duplicate evidence omitted')
 var many=[]
 for i in range(49):many.append({'kind':'text','text':'No match '+str(i)})
 many[48].text='unique keyword'
 check(not JSON.stringify(Selection.take('unique keyword',many,2400)).contains('unique keyword'),'Selection never expands native48block boundary')
 var app=root.get_node('App');app.cancel();app.set_locale('en')
 var originals=[app.provider,app.local_runtime,app.provider_name,app.application_access.target.duplicate(true)]
 var provider=Capture.new();var runtime=Runtime.new();app.add_child(provider);app.add_child(runtime)
 app.provider=provider;app.local_runtime=runtime;app.provider_name='local_worker';app.application_access.target=target
 app.window_read_target=target;app.window_read_question='What is the budget?';app.window_read_mode='observing'
 var history=app.session_turns.duplicate(true)
 app._window_read_observed({'target':target,'blocks':[{'kind':'text','text':'Budget42.'}],'observed_ms':Time.get_ticks_msec()})
 check(app.window_read_mode=='thinking' and provider.calls.size()==1,'RealApp submits one evidence request')
 app._on_answer(answer('Budget999.'))
 check(app.window_read_mode.is_empty() and app.state.current=='idle' and not runtime.generation_busy,'Rejected answer releases worker and job')
 check(app.t('window_read_unverified') in app.messages[-1].text and 'Budget42.' in app.messages[-1].text and not '999' in app.messages[-1].text,'Rejected prose hidden; original excerpt fallback labelled')
 check(app.messages[-1].get('ephemeral',false) and app.session_turns==history,'Fallback never enters persistent reusable history')
 check(provider.calls.size()==1,'No extra inference for fallback')
 app.window_read_target=target;app.window_read_question='q';app.window_read_mode='observing'
 app._window_read_observed({'target':target,'blocks':[{'kind':'text','text':'old'}],'observed_ms':Time.get_ticks_msec()+500})
 check(app.window_read_mode.is_empty() and provider.calls.size()==1,'Future snapshot rejected before model submission')
 app.window_read_target=target;app.window_read_question='q';app.window_read_mode='observing'
 app._window_read_observed({'target':target,'blocks':[{'kind':'text','text':'Budget42.'}],'observed_ms':Time.get_ticks_msec()});app.cancel();var count=app.messages.size();app._on_answer(answer('Budget999.'))
 check(app.messages.size()==count,'Cancelled late response cannot reveal fallback')
 app.provider=originals[0];app.local_runtime=originals[1];app.provider_name=originals[2];app.application_access.target=originals[3];provider.queue_free();runtime.queue_free()
 print('EVIDENCE021: %d checks, %d failures; fake generation, not semantic truth proof' %[checks,failures]);quit(0 if failures==0 else 1)
