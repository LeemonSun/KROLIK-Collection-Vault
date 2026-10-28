extends SceneTree
const Draft=preload('res://src/core/chat_draft.gd')
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
 for query in ['Составь короткое приглашение на встречу завтра.','Напиши письмо с благодарностью за помощь.','Составь объявление: библиотека закрыта в пятницу.','Compose a short invitation.','Draft a short notice.','Write a thank-you email.','请写一句邀请明天参加会议的话。','请写邀请：明天14:30在A室开会。','请写一封简短的感谢邮件。']:
  check(Draft.requested(query),'Practical text scope '+query)
 for query in ['Расскажи о кошках','Напиши рассказ с приглашением в замок','Придумай приглашение с выдуманными датами','Переведи письмо','Write a story about an invitation','Write code to parse an email','Draft the same invitation as above','Составь такое приглашение как выше','Compose a long email','Compose an email in 500 words','请写一篇虚构的邀请故事','请写一封500字的邮件','Do not write an email','Составь письмо? И что такое мудрость?']:
  check(not Draft.requested(query),'General/creative/context-dependent requests keep ordinary dialogue '+query)
 check(Draft.problems('Tomorrow at 3 PM.','Compose an invitation tomorrow').has('3'),'Unsupported time detected')
 check(not Draft.problems('Приглашение отправлено.','Составь приглашение.').is_empty(),'Passive invitation action claim detected')
 check(not Draft.problems('The invitation was sent.','Compose an invitation.').is_empty(),'English passive invitation claim detected')
 check(not Draft.problems('邀请已发送。','请写邀请。').is_empty(),'Chinese passive invitation claim detected')
 check(Draft.problems('You are invited tomorrow at 14:30 in room A.','Compose invitation tomorrow at 14:30 in room A.').is_empty(),'Supplied facts retained')
 check(Draft.problems(12,'Compose an email').size()==1,'Invalid draft type handled')
 var managed=preload('res://src/runtime/local_runtime.gd').new()
 managed.manifest=JSON.parse_string(FileAccess.get_file_as_string('res://config/local_worker.json'))
 var args=managed.build_args({'context_tokens':2048,'cpu_threads':2})
 check(args[args.find('--cache-ram')+1]=='0' and args[args.find('--ctx-checkpoints')+1]=='0','Owned worker explicitly disables extra RAM prompt cache/checkpoints')
 managed.free()
 var app=root.get_node('App');app.cancel();app.set_locale('en')
 var original=[app.provider,app.local_runtime,app.provider_name,app.local_ai_enabled,app.session_turns.duplicate(true)]
 var capture=Capture.new();var runtime=Runtime.new();app.add_child(capture);app.add_child(runtime)
 app.provider=capture;app.local_runtime=runtime;app.provider_name='local_worker';app.local_ai_enabled=true;app.session_turns=[]
 app.submit('Compose a short invitation for a meeting tomorrow.')
 check(app.chat_draft_mode and capture.calls.size()==1 and not capture.calls[0].options.get('companion_dialogue',false),'Practical authoring bypasses persona sampler')
 check(capture.calls[0].messages.size()==2 and not 'User OS:' in capture.calls[0].messages[0].content,'Authoring has only task and factual constraints')
 var count=app.messages.size()
 app._on_answer('Tomorrow at 3 PM in the office.')
 check(app.chat_draft_attempt==2 and capture.calls.size()==2 and app.messages.size()==count,'Rejected draft stays hidden during one correction')
 check(app.session_turns.is_empty(),'Rejected draft never enters model conversation history')
 app._on_answer('You are invited to a meeting tomorrow.')
 check(not app.chat_draft_mode and app.state.current=='idle' and app.messages[-1].text.begins_with(app.t('chat_draft_heading')),'Delivered text clearly labelled as an unsent draft')
 check(app.session_turns[-1].content=='You are invited to a meeting tomorrow.','Only accepted body enters history')
 app.submit('Draft a short invitation tomorrow.');app._on_answer('The invitation was sent.');app._on_answer('Invitation sent.')
 check(app.state.current=='idle' and app.messages[-1].text==app.t('chat_draft_unverified') and not app.chat_draft_mode,'Second unsupported result stops without fake delivery')
 app.submit('Write a short email thanking someone for help.');app.cancel();count=app.messages.size();app._on_answer('Late canceled draft.')
 check(app.messages.size()==count and not app.chat_draft_mode,'Cancel suppresses late draft')
 app.submit('Explain why the sky is blue.')
 check(not app.chat_draft_mode and 'well-established knowledge' in capture.calls[-1].messages[0].content,'General factual dialogue prompt remains unchanged')
 app.cancel();app.provider=original[0];app.local_runtime=original[1];app.provider_name=original[2];app.local_ai_enabled=original[3];app.session_turns=original[4]
 capture.queue_free();runtime.queue_free()
 print('CHAT_DRAFT020: %d checks, %d failures; actual App with fake generation, not IQ proof' %[checks,failures])
 quit(0 if failures==0 else 1)
