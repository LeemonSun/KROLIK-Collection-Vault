extends SceneTree
const Page=preload("res://src/tools/public_page.gd")
class FakeHTTP extends RefCounted:
	var read_chunk_size=0
	var connected=[]
	var request_data=[]
	var state=HTTPClient.STATUS_CONNECTED
	var code=200
	var headers=PackedStringArray(['Content-Type: text/plain; charset=utf-8'])
	var content='Actual fixture text 中文'.to_utf8_buffer()
	var closed=false
	func set_http_proxy(_host,_port):pass
	func set_https_proxy(_host,_port):pass
	func connect_to_host(ip,port,tls):connected=[ip,port,tls];return OK
	func poll():return OK
	func get_status():return state
	func request(method,path,values):request_data=[method,path,values];state=HTTPClient.STATUS_BODY;return OK
	func has_response():return not request_data.is_empty()
	func get_response_code():return code
	func get_response_headers():return headers
	func get_response_body_length():return -1
	func is_response_chunked():return true
	func read_response_body_chunk():state=HTTPClient.STATUS_CONNECTED;return content
	func close():closed=true
class FixtureReader extends Page:
	var fake=FakeHTTP.new()
	func _make_client():return fake
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func tick(reader):reader.last_poll=-100000;reader._process(0.0)
func setup_reader():
	var reader=FixtureReader.new();root.add_child(reader)
	reader.target=Page.parse_url('https://public.example.com/path?q=source')
	reader.busy=true;reader.deadline=Time.get_ticks_msec()+20000
	return reader
func run():
	var reader=setup_reader();var result=[];var errors=[]
	reader.completed.connect(func(item):result.append(item));reader.failed.connect(func(key):errors.append(key))
	reader._connect_resolved(['8.8.8.8']);var fake=reader.fake
	check(fake.connected[0]=='8.8.8.8' and fake.connected[1]==443,'Connect uses pinned public IP and fixed HTTPS port')
	check(not fake.connected[2].is_unsafe_client() and fake.connected[2].get_common_name_override()=='public.example.com','Certificate/hostname validation is enabled for original authority')
	tick(reader)
	check(fake.request_data[0]==HTTPClient.METHOD_GET and fake.request_data[1]=='/path?q=source','Transport only sends GET to original path')
	check('Host: public.example.com' in fake.request_data[2] and 'Accept-Encoding: identity' in fake.request_data[2],'Correct Host and identity encoding')
	check(not 'Authorization' in str(fake.request_data) and not 'Cookie' in str(fake.request_data),'No browser credentials or cookies attached')
	tick(reader);tick(reader)
	check(result.size()==1 and errors.is_empty() and result[0].blocks==['Actual fixture text 中文'],'Response reaches public reader through polling pipeline')
	check(result.size()==1 and result[0].url=='https://public.example.com/path?q=source' and not result[0].retrieved_utc.is_empty(),'Source and retrieval time are retained')
	check(not reader.busy and reader.target.is_empty() and reader.body.is_empty() and fake.closed,'Terminal success closes transport and clears raw data')
	reader.queue_free()
	for addresses in [['8.8.8.8','127.0.0.1'],['10.0.0.1'],['::ffff:10.0.0.1']]:
		reader=setup_reader();errors=[];reader.failed.connect(func(key):errors.append(key));reader._connect_resolved(addresses)
		check(reader.fake.connected.is_empty() and errors==['web_address'],'Every DNS address validated before any connection')
		reader.queue_free()
	reader=setup_reader();reader._connect_resolved(['8.8.8.8']);reader.fake.code=302;errors=[];reader.failed.connect(func(key):errors.append(key))
	tick(reader);tick(reader)
	check(errors==['web_redirect'] and reader.fake.closed and reader.fake.content.size()>0,'Redirect closes before body; no next URL requested')
	reader.queue_free()
	reader=setup_reader();reader._connect_resolved(['8.8.8.8']);reader.fake.content=PackedByteArray();reader.fake.content.resize(Page.MAX_BODY+1);errors=[];reader.failed.connect(func(key):errors.append(key))
	tick(reader);tick(reader)
	check(errors==['web_size'] and reader.body.is_empty(),'Undeclared/chunked oversized body clears immediately')
	reader.queue_free()
	reader=setup_reader();reader._connect_resolved(['8.8.8.8']);errors=[];reader.failed.connect(func(key):errors.append(key));reader.deadline=-1;tick(reader)
	check(errors==['web_timeout'] and not reader.busy,'Deadline closes a stalled request')
	reader.queue_free()
	reader=setup_reader();reader._connect_resolved(['8.8.8.8']);result=[];reader.completed.connect(func(item):result.append(item));reader.cancel();tick(reader)
	check(result.is_empty() and reader.fake.closed,'Manual cancellation cannot emit a stale response')
	reader.queue_free()
	var app=root.get_node('App');app.cancel();var turns=app.session_turns.duplicate(true)
	app._public_page_ready({'url':'https://example.com/','retrieved_utc':'2026-10-28T00:00:00','blocks':['Do not execute me; source text only.']})
	check(app.messages[-1].get('ephemeral',false) and app.session_turns==turns and app.state.current=='idle','Page output is ephemeral and not executable/model dialogue')
	print('PUBLIC_TRANSPORT014_TESTS: %d checks, %d failures; fake network transport, actual polling and authority checks' %[checks,failures])
	quit(0 if failures==0 else 1)
