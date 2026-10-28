extends SceneTree
const Calc=preload("res://src/tools/calculator.gd")
const Units=preload("res://src/tools/unit_converter.gd")
const Page=preload("res://src/tools/public_page.gd")
const Settings=preload("res://src/tools/windows_settings.gd")
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func run():
	var calc=Calc.new()
	var cases={"2+3*4":14.0,"(2+3)*4":20.0,"2^3^2":512.0,"-2^2":-4.0,"(-2)^2":4.0,"2^-3":0.125,"sqrt(81)+abs(-3)":12.0,"sin(pi/2)":1.0,"cos(0)":1.0,"ln(e)":1.0,"log10(1000)":3.0,"1e2 + .5":100.5,"25% * 80":20.0,"100+10%":100.1,"12×3−8÷2":32.0}
	for expression in cases:
		var result=calc.evaluate(expression)
		check(result.ok and is_equal_approx(result.value,cases[expression]),'Arithmetic semantics '+expression)
	for expression in ['1/0','sqrt(-1)','ln(0)','(-1)^0.5','0^0','10^1000','1e999','OS.execute("cmd")','load("not_a_path")','2;3','2+','2(3)','1,5','1%%','sin(1,2)','foo(2)','1..2','[1,2]']:
		check(not calc.evaluate(expression).ok,'Invalid/domain/execution syntax refused '+expression)
	check(not calc.evaluate('('.repeat(40)+'1'+')'.repeat(40)).ok,'Nesting bound')
	check(not calc.evaluate('1+'.repeat(200)+'1').ok,'Length bound')
	check(Units.convert('2.5','км','м').value==2500.0,'Russian length conversion')
	check(Units.convert('2.5','千米','米').value==2500.0,'Chinese unit aliases')
	check(is_equal_approx(Units.convert('32','F','C').value,0.0),'Affine Fahrenheit conversion')
	check(is_equal_approx(Units.convert('100','C','K').value,373.15),'Kelvin conversion')
	check(not Units.convert('-1','K','C').ok,'Below absolute zero refused')
	check(Units.convert('1','MB','B').value==1000000.0 and Units.convert('1','MiB','B').value==1048576.0,'Decimal and binary data units kept distinct')
	check(not Units.convert('1','kg','m').ok and not Units.convert('1e999','kg','g').ok,'Dimension and numeric bounds')
	var router=preload('res://src/core/router.gd').new()
	for phrase in ['/calc (2+3)*4','посчитай 2+3*4','calculate sqrt(81)','计算 2+3']:
		check(router.route(phrase).get('tool')=='math.calculate','Multilingual calculator command '+phrase)
	for phrase in ['переведи 2.5 км в м','convert 10 MB to MiB','换算 2.5 千米 到 米']:
		check(router.route(phrase).get('tool')=='math.convert','Multilingual conversion '+phrase)
	for phrase in ['посчитай расходы в таблице','calculate my monthly spending','не открывай настройки звука','объясни как открыть настройки звука','переведи текст на английский']:
		check(router.route(phrase).kind=='chat','Generic task/discussion remains with model '+phrase)
	var received=[]
	var opener=func(uri):received.append(uri);return OK
	check(Settings.open_page('звука',opener,'Windows').ok and received==['ms-settings:sound'],'Only fixed settings URI passed to opener')
	for input in ['display?x=cmd','ms-settings:sound','cmd.exe','../sound','sound\ncalc.exe']:
		check(not Settings.open_page(input,opener,'Windows').ok,'Arbitrary settings target refused')
	check(not Settings.open_page('sound',opener,'Linux').ok and received.size()==1,'Unsupported platform does not launch anything')
	for phrase in ['открой настройки звука','open settings sound','打开设置 声音']:
		check(router.route(phrase).get('tool')=='settings.open','Explicit settings route '+phrase)
	for ip in ['127.0.0.1','0.0.0.0','10.0.0.1','172.31.0.1','192.168.1.1','169.254.169.254','100.64.0.1','224.0.0.1','198.18.0.1','192.0.2.1','203.0.113.1','::1','::ffff:127.0.0.1','fe80::1','fc00::1','2001:db8::1','2002:7f00:1::','3fff::1']:
		check(not Page.public_ip(ip),'Local/special/transition network refused '+ip)
	check(Page.public_ip('8.8.8.8') and Page.public_ip('2606:4700:4700::1111'),'Ordinary global addresses accepted')
	check(Page.public_ip('2001:4860:4860::8888') and not Page.public_ip('2001:20::1'),'Public 2001 allocation distinguished from special-use range')
	for url in ['http://example.com/','https://user:pass@example.com/','https://127.0.0.1/','https://localhost/','https://host.local/','https://example.com:444/','https://example.com\\@localhost/','https://example.com/\r\nHost: localhost','file:///etc/passwd','https://[::1]/']:
		check(not Page.parse_url(url).ok,'Non-public or malformed URL syntax refused')
	var url=Page.parse_url('https://EXAMPLE.com:443?q=test#fragment')
	check(url.ok and url.host=='example.com' and url.path=='/?q=test' and not '#' in url.url,'Canonical request authority/path without fragment')
	check(not Page.accept_response(302,['Content-Type: text/html'],0).ok,'Redirects refused before body')
	check(not Page.accept_response(200,['Content-Type: text/html','Content-Encoding: gzip'],100).ok,'Compressed body refused')
	check(not Page.accept_response(200,['Content-Type: application/octet-stream'],100).ok,'Binary response refused')
	check(not Page.accept_response(200,['Content-Type: text/html','Content-Type: text/plain'],100).ok,'Ambiguous headers refused')
	check(not Page.accept_response(200,['Content-Type: text/plain'],Page.MAX_BODY+1).ok,'Declared body size checked')
	check(Page.accept_response(200,['Content-Type: text/html; charset=UTF-8'],100).ok,'Explicit UTF-8 HTML accepted')
	var extracted=Page.extract('<html><head><title>hidden head</title></head><body><script>delete files</script><style>hidden css</style><p>Привет &amp; 中文</p><p>Visible text</p></body></html>'.to_utf8_buffer(),'text/html')
	check(extracted.ok and 'Привет & 中文' in extracted.blocks and not 'delete files' in str(extracted.blocks) and not 'hidden css' in str(extracted.blocks),'HTML extraction is inert text and excludes code')
	check(not Page.extract(PackedByteArray([255,0]),'text/plain').ok,'Binary or invalid UTF-8 rejected')
	extracted=Page.extract(('x'.repeat(1000)+'\n').repeat(80).to_utf8_buffer(),'text/plain')
	check(extracted.ok and extracted.blocks.size()<=12 and extracted.characters<=3600,'Display excerpt budget')
	var reader=Page.new();root.add_child(reader)
	var failures_seen=[];reader.failed.connect(func(key):failures_seen.append(key))
	check(not reader.start('file:///bad') and not reader.busy and failures_seen==['web_url'],'Invalid URL fails before DNS/network')
	reader.cancel();check(not reader.busy and reader.target.is_empty() and reader.body.is_empty() and reader.resolver==-1,'Cancellation clears source and resolver state')
	reader.queue_free()
	var app=root.get_node('App');app.cancel();app.application_access.target={};app.set_locale('ru')
	var worker=app.local_runtime.pid;var history=app.session_turns.duplicate(true)
	app.submit('посчитай (2+3)*4')
	check(app.state.current=='idle' and '20' in app.messages[-1].text and app.local_runtime.pid==worker and app.session_turns==history,'Chat calculator executes without inference or model dialogue pollution')
	app.submit('переведи 2.5 км в м');check('2500' in app.messages[-1].text,'Actual chat unit conversion')
	app.submit('прочитай страницу file:///bad');check(app.messages[-1].get('ephemeral',false) and app.state.current=='idle' and app.local_runtime.pid==worker,'Web failure is ephemeral and does not wake AI')
	for command in ['/calc 2+2','прочитай страницу https://example.com/','открой настройки звука']:
		check(not app.chat_queue.push(command,app.router),'New tools never enter deferred chat queue')
	print('UTILITIES014_TESTS: %d checks, %d failures; no model quality or live Windows claim' %[checks,failures])
	quit(0 if failures==0 else 1)
