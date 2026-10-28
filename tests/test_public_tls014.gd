extends SceneTree
const Page=preload("res://src/tools/public_page.gd")
class LocalTLSClient extends RefCounted:
	# Test-only adapter: the production reader still validates a public IP.
	# Only this fixture routes the socket to our private local TLS server.
	var inner=HTTPClient.new()
	var read_chunk_size=4096:
		set(value):read_chunk_size=value;inner.read_chunk_size=value
	func set_http_proxy(host,port):inner.set_http_proxy(host,port)
	func set_https_proxy(host,port):inner.set_https_proxy(host,port)
	func connect_to_host(_ip,_port,tls):
		var ca=X509Certificate.new()
		if ca.load(OS.get_environment('LEEMON_TEST_CA'))!=OK:return FAILED
		return inner.connect_to_host('127.0.0.1',int(OS.get_environment('LEEMON_TEST_TLS_PORT')),TLSOptions.client(ca,tls.get_common_name_override()))
	func poll():return inner.poll()
	func get_status():return inner.get_status()
	func request(method,path,headers):return inner.request(method,path,headers)
	func has_response():return inner.has_response()
	func get_response_code():return inner.get_response_code()
	func get_response_headers():return inner.get_response_headers()
	func get_response_body_length():return inner.get_response_body_length()
	func is_response_chunked():return inner.is_response_chunked()
	func read_response_body_chunk():return inner.read_response_body_chunk()
	func close():inner.close()
class TLSReader extends Page:
	func _make_client():return LocalTLSClient.new()
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func fetch(path):
	var reader=TLSReader.new();root.add_child(reader);var results=[];var errors=[]
	reader.completed.connect(func(item):results.append(item));reader.failed.connect(func(key):errors.append(key))
	reader.target=Page.parse_url('https://public.example.com'+path);reader.busy=true;reader.deadline=Time.get_ticks_msec()+5000;reader._connect_resolved(['8.8.8.8'])
	var start=Time.get_ticks_msec()
	while reader.busy and Time.get_ticks_msec()-start<6000:await process_frame
	var clean=reader.target.is_empty() and reader.body.is_empty();reader.cancel();reader.queue_free()
	return {"results":results,"errors":errors,"clean":clean}
func run():
	var result=await fetch('/good')
	check(result.errors.is_empty() and result.results.size()==1,'Real TLS socket and hostname certificate verification complete')
	if result.results.size()==1:
		check('Документ & 中文' in result.results[0].blocks,'Actual HTTPS HTML bytes decoded and extracted')
		check(result.results[0].url=='https://public.example.com/good' and result.clean,'Actual response preserves source and clears raw bytes')
	result=await fetch('/chunked')
	check(result.errors.is_empty() and result.results.size()==1,'Real chunked HTTPS response consumed to completion')
	if result.results.size()==1:check('first second' in str(result.results[0].blocks),'Chunk boundaries do not corrupt UTF-8 body')
	result=await fetch('/redirect')
	check(result.results.is_empty() and result.errors==['web_redirect'] and result.clean,'Actual redirect to private target is not followed')
	result=await fetch('/large')
	check(result.results.is_empty() and result.errors==['web_size'] and result.clean,'Actual declared oversized response refused')
	print('PUBLIC_TLS014_TESTS: %d checks, %d failures; actual local TLS server, test-only socket adapter; public DNS/live websites not verified' %[checks,failures])
	quit(0 if failures==0 else 1)
