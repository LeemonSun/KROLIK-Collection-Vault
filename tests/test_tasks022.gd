extends SceneTree
var checks=0
var failures=0
class Access extends 'res://src/tools/application_access.gd':
 var inspected=0
 func inspect(_silent=false):inspected+=1;return true
class Desktop extends Node:
 var requested=""
 signal completed(result)
 func request(value):requested=value;return true
 func cancel():pass
class Vpn extends Node:
 var requested=[]
 func connect_profile(value=""):requested.append(value);return true
 func cancel():pass
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func run():
 var router=preload('res://src/core/router.gd').new()
 for text in ['найди во вкладках SoundCloud','открой браузер и найди мне там во вкладках саунклауд','find tab SoundCloud','open browser tab SoundCloud','打开标签页SoundCloud','найд во вкладках SoundCloud']:
  var result=router.route(text);check(result.get('tool')=='desktop.task' and result.get('args',{}).get('action')=='tabs','Tab intent '+text)
 for text in ['включи впн','connect vpn Work','连接VPN']:
  check(router.route(text).get('args',{}).get('action')=='vpn','VPN intent '+text)
 for text in ['открой Proton VPN и нажми Подключить','launch Notepad and click New','启动记事本并点击新建']:
  check(router.route(text).get('args',{}).get('action')=='launch_goal','Launch then agent '+text)
 for text in ['не включи впн','как включить впн?','не найди во вкладках SoundCloud','расскажи про вкладки','find tab x','найди во вкладках '+ 'x'.repeat(101)]:
  check(router.route(text).get('tool')!='desktop.task','No task effects '+text.left(60))
 var tabs=preload('res://src/tools/browser_tabs.gd').new();root.add_child(tabs)
 var identity={'handle':'123','target_pid':234,'started':'345','title':'Browser','app':'opera'}
 var node={'id':'1,2','name':'SoundCloud music','type':'ControlType.TabItem','automation_id':'tab','ancestors':[]}
 tabs.query='саунклауд'
 check(tabs.matches({'tabs':[{'identity':identity,'node':node},{'identity':identity,'node':node.merged({'name':'Other'},true)},'malformed']}).size()==1,'Aliases matched without interpreting model text')
 tabs.observed_ms=Time.get_ticks_msec()-31000;check(not tabs.choose(0),'Expired candidate rejected')
 tabs.forget();check(tabs.candidates.is_empty() and tabs.query.is_empty(),'Forget clears titles/query')
 var app=root.get_node('App');app.cancel()
 var old_access=app.application_access;var old_desktop=app.desktop_actions;var old_vpn=app.vpn_connection
 var vpn=Vpn.new();app.add_child(vpn);app.vpn_connection=vpn
 var access=Access.new();app.add_child(access);var desktop=Desktop.new();app.add_child(desktop)
 app.application_access=access;app.desktop_actions=desktop
 app.submit('открой Proton VPN и нажми Подключить')
 check(desktop.requested=='Proton VPN' and app.launch_goal=='нажми Подключить','Literal launch/goal preserved')
 app._desktop_completed({'status':'visible','identity':identity})
 check(access.target==identity and access.inspected==1 and app.goal_mode=='observing' and app.agent.active,'Visible launch hands actual identity into shared observation loop')
 app.cancel();check(app.launch_goal.is_empty() and not app.agent.active,'Stop clears chained goal')
 app.submit('открой Proton VPN и нажми Подключить');app._desktop_completed({'status':'started'})
 check(app.launch_goal.is_empty() and not app.agent.active and app.state.current=='idle','Unverified launch cannot continue agent')
 app.submit('открой Proton VPN и нажми Подключить');app.cancel();app._desktop_completed({'status':'visible','identity':identity})
 check(not app.agent.active and app.launch_goal.is_empty(),'Late receipt after stop cannot start agent')
 app.state.transition('executing');app.browser_tabs.query='SoundCloud';app._tabs_completed({'status':'tabs','tabs':[{'identity':identity,'node':node},{'identity':identity,'node':node.merged({'id':'1,3'},true)}]})
 check(app.state.current=='idle' and app.browser_tabs.candidates.size()==2,'Multiple matches require choice')
 app.submit('/help');check(app.browser_tabs.candidates.is_empty(),'New user task revokes old choices')
 app.cancel()
 for text in ['открой Steam и включи впн Work','open Steam and connect vpn Work','启动Steam并连接VPN']:
  app.submit(text);check(desktop.requested=='Steam' and not app.launch_vpn.is_empty(),'Two-stage launch '+text)
  var before=vpn.requested.size();app._desktop_completed({'status':'visible'})
  check(vpn.requested.size()==before+1 and app.launch_vpn.is_empty(),'VPN stage starts only after visible launch')
  app.cancel()
 app.submit('открой Steam и включи впн');var count=vpn.requested.size();app._desktop_completed({'status':'started'})
 check(vpn.requested.size()==count and app.launch_vpn.is_empty(),'Unverified launch does not connect VPN')
 app.submit('открой Steam и включи впн');app.cancel();app._desktop_completed({'status':'visible'})
 check(vpn.requested.size()==count and app.launch_vpn.is_empty(),'Cancelled chain does not connect VPN')
 app.application_access=old_access;app.desktop_actions=old_desktop;app.vpn_connection=old_vpn;access.queue_free();desktop.queue_free();vpn.queue_free()
 # Real helper transport on Linux validates nonce/request/result plumbing only.
 var runner=OS.get_environment('COMPANION_PWSH')
 if not runner.is_empty():
  for helper in [tabs,preload('res://src/tools/vpn_connection.gd').new()]:
   if not helper.is_inside_tree():root.add_child(helper)
   helper.runner=runner;helper.test_runner=true
   if helper==tabs:helper.find_tabs('SoundCloud')
   else:helper.connect_profile('Work')
   var result=await helper.completed
   check(result.status=='unsupported' and str(result.get('nonce','')).length()==32,'Actual PowerShell nonce roundtrip '+helper.helper_resource)
   if helper!=tabs:helper.queue_free()
 tabs.queue_free()
 print('TASKS022: %d checks, %d failures; synthetic UIA + optional Linux PowerShell, not Windows acceptance' %[checks,failures]);quit(0 if failures==0 else 1)
