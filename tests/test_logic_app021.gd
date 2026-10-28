extends SceneTree
var checks=0
var failures=0
class Capture extends Node:
 var calls=[]
 func submit(messages,options):calls.append({'messages':messages.duplicate(true),'options':options.duplicate(true)});return true
 func cancel():pass
class Runtime extends Node:
 var status='ai_ready'
 var generation_busy=false
 var manifest={}
 func installed():return true
 func touch():pass
 func stop():pass
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func run():
 var app=root.get_node('App');app.cancel();app.set_locale('en');app.application_access.target={}
 var old=[app.provider,app.local_runtime,app.provider_name,app.local_ai_enabled,app.session_turns.duplicate(true)]
 var provider=Capture.new();var runtime=Runtime.new();app.add_child(provider);app.add_child(runtime)
 app.provider=provider;app.local_runtime=runtime;app.provider_name='local_worker';app.local_ai_enabled=true;app.session_turns=[];check(not app.store.data.settings.get('experimental_logic_formalization',false),'Unreliable model interpreter off by default');app.store.data.settings['experimental_logic_formalization']=true
 var question='Все большие роботы устройства. Некоторые устройства красные. Следует ли, что некоторые большие роботы красные?'
 var proposal={'premises':[{'kind':'all','subject':'большие роботы','predicate':'устройства','quote':'Все большие роботы устройства.'},{'kind':'some','subject':'устройства','predicate':'красные','quote':'Некоторые устройства красные.'}],'conclusion':{'kind':'some','subject':'большие роботы','predicate':'красные'}}
 app.submit(question)
 check(app.logic_mode and provider.calls.size()==1,'Categorical chat uses one formalization inference')
 check(provider.calls[0].messages.size()==2 and provider.calls[0].options.has('response_schema') and not provider.calls[0].options.has('reasoning_tokens'),'No hidden thinking, persona history or extra worker')
 check(runtime.generation_busy and app.state.current=='thinking','Owned runtime busy during formalization')
 app._on_answer(JSON.stringify(proposal))
 check(not app.logic_mode and app.state.current=='idle' and not runtime.generation_busy,'Solver result releases managed job')
 check('does not follow' in app.messages[-1].text and 'All «большие роботы» are «устройства»' in app.messages[-1].text,'Output shows interpretation and deterministic verdict')
 check(not '"premises"' in app.messages[-1].text and not '"supported"' in app.messages[-1].text,'Internal JSON never displayed')
 check(app.session_turns.size()==2 and app.session_turns[-1].content==app.messages[-1].text,'Only final human-readable interpretation enters history')
 app.submit(question);var before=app.messages.size();app._on_answer('{"premises":[],"conclusion":{"kind":"all","subject":"","predicate":""}}')
 check(not app.logic_mode and app.messages.size()==before+1 and app.messages[-1].text==app.t('logic_unverified'),'Unsupported interpretation gets an honest bounded failure')
 check(provider.calls.size()==2 and app.session_turns.size()==2,'No speculative retry or failed raw context retention')
 app.submit(question);app.cancel();before=app.messages.size();app._on_answer(JSON.stringify(proposal))
 check(not app.logic_mode and app.messages.size()==before,'Canceled interpretation cannot create a late answer')
 app.submit('Why is the sky blue?')
 check(not app.logic_mode and not provider.calls[-1].options.has('response_schema'),'Other knowledge questions keep ordinary reasoning path')
 app.cancel();app.submit('Compose a short invitation tomorrow.')
 check(app.chat_draft_mode and not app.logic_mode,'Practical authoring remains separate')
 app.cancel();app.store.data.settings.erase('experimental_logic_formalization');app.provider=old[0];app.local_runtime=old[1];app.provider_name=old[2];app.local_ai_enabled=old[3];app.session_turns=old[4];provider.queue_free();runtime.queue_free()
 print('LOGIC_APP021: %dchecks,%dfailures; actualAppwithfakeinterpretation, not model quality' %[checks,failures]);quit(0 if failures==0 else 1)
