extends Node
## Explicit public HTTPS GET. Pinned resolved IP, validated TLS hostname, no browser session.
signal completed(result)
signal failed(key)
signal changed
const MAX_BODY=262144
var busy=false
var stage=""
var target={}
var resolver=-1
var client
var deadline=0
var body=PackedByteArray()
var response_started=false
var expected_length=-1
var last_poll=0
static func parse_url(raw):
	if not raw is String or raw.length()>2048:return {"ok":false,"status":"url"}
	for i in range(raw.length()):
		if raw.unicode_at(i)<33 or raw.unicode_at(i)>126 or raw[i]=="\\":return {"ok":false,"status":"url"}
	var rx=RegEx.new();rx.compile('^https://([A-Za-z0-9.-]+)(?::443)?([/?][^#]*)?(?:#[^#]*)?$')
	var hit=rx.search(raw)
	if hit==null:return {"ok":false,"status":"url"}
	var host=hit.get_string(1).to_lower()
	if host.length()>253 or not "." in host or host.is_valid_ip_address() or host.ends_with("."):return {"ok":false,"status":"url"}
	for label in host.split("."):
		var domain=RegEx.new();domain.compile('^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$')
		if domain.search(label)==null:return {"ok":false,"status":"url"}
	for suffix in [".localhost",".local",".internal",".lan",".home",".test",".invalid"]:
		if host.ends_with(suffix):return {"ok":false,"status":"url"}
	var path=hit.get_string(2)
	if path.is_empty():path="/"
	elif path.begins_with("?"):path="/"+path
	return {"ok":true,"host":host,"path":path,"url":"https://"+host+path}
static func public_ip(raw):
	if not raw is String or not raw.is_valid_ip_address():return false
	if ":" in raw:
		# Conservative global IPv6 only; no mapped IPv4, local, transition or doc ranges.
		var ip=raw.to_lower()
		if "." in ip or "%" in ip:return false
		var first=ip.get_slice(":",0).hex_to_int()
		if first<0x2000 or first>0x3fff:return false
		if first in [0x2002,0x3fff] or ip.begins_with("3ffe:"):return false
		if first==0x2001:
			var word=ip.get_slice(":",1);var second=0 if word.is_empty() else word.hex_to_int()
			if second<=0x01ff or second==0x0db8:return false
		return true
	var parts=raw.split(".")
	if parts.size()!=4:return false
	var n=[]
	for item in parts:
		if str(int(item))!=item:return false
		n.append(int(item))
	if n[0] in [0,10,127] or n[0]>=224:return false
	if n[0]==100 and n[1]>=64 and n[1]<=127:return false
	if n[0]==169 and n[1]==254:return false
	if n[0]==172 and n[1]>=16 and n[1]<=31:return false
	if n[0]==192 and (n[1]==168 or (n[1]==0 and n[2] in [0,2]) or (n[1]==88 and n[2]==99)):return false
	if n[0]==198 and (n[1] in [18,19] or (n[1]==51 and n[2]==100)):return false
	if n[0]==203 and n[1]==0 and n[2]==113:return false
	return true
func start(url):
	if busy:return false
	var parsed=parse_url(url)
	if not parsed.ok:failed.emit("web_url");return false
	target=parsed;body=PackedByteArray();response_started=false
	resolver=IP.resolve_hostname_queue_item(target.host,IP.TYPE_ANY)
	if resolver==IP.RESOLVER_INVALID_ID:target={};failed.emit("web_connection");return false
	busy=true;stage="resolving";deadline=Time.get_ticks_msec()+20000;changed.emit();return true
func _process(_delta):
	if not busy or Time.get_ticks_msec()<last_poll+25:return
	last_poll=Time.get_ticks_msec()
	if last_poll>deadline:_fail("web_timeout");return
	if resolver>=0:
		var status=IP.get_resolve_item_status(resolver)
		if status==IP.RESOLVER_STATUS_WAITING:return
		if status!=IP.RESOLVER_STATUS_DONE:_fail("web_connection");return
		var addresses=IP.get_resolve_item_addresses(resolver);IP.erase_resolve_item(resolver);resolver=-1
		if addresses.is_empty():_fail("web_connection");return
		_connect_resolved(addresses);return

	if client==null:_fail("web_connection");return
	if client.poll()!=OK:_fail("web_connection");return
	var status=client.get_status()
	if status in [HTTPClient.STATUS_CANT_CONNECT,HTTPClient.STATUS_CONNECTION_ERROR,HTTPClient.STATUS_TLS_HANDSHAKE_ERROR,HTTPClient.STATUS_CANT_RESOLVE]:_fail("web_connection");return
	if stage=="connecting" and status==HTTPClient.STATUS_CONNECTED:
		var headers=PackedStringArray(["Host: "+target.host,"User-Agent: Leemon/0.14 (explicit page reader)","Accept: text/html,text/plain;q=0.9","Accept-Encoding: identity"])
		if client.request(HTTPClient.METHOD_GET,target.path,headers)!=OK:_fail("web_connection");return
		stage="reading";changed.emit();return
	if stage!="reading":return
	if client.has_response() and not response_started:
		response_started=true
		var accepted=accept_response(client.get_response_code(),client.get_response_headers(),client.get_response_body_length())
		if not accepted.ok:_fail("web_"+accepted.status);return
		expected_length=-1 if client.is_response_chunked() else client.get_response_body_length()
		if expected_length<0 and not client.is_response_chunked():_fail("web_content");return
		target["content_type"]=accepted.content_type
	if response_started:
		if status==HTTPClient.STATUS_BODY:
			var chunk=client.read_response_body_chunk()
			if body.size()+chunk.size()>MAX_BODY:_fail("web_size");return
			body.append_array(chunk)
			if expected_length>=0 and body.size()==expected_length:_finish();return
		elif status in [HTTPClient.STATUS_DISCONNECTED,HTTPClient.STATUS_CONNECTED]:_finish()
	elif status==HTTPClient.STATUS_DISCONNECTED:_fail("web_connection")
func _make_client():return HTTPClient.new()
func _connect_resolved(addresses):
	if addresses.is_empty():_fail("web_connection");return
	for address in addresses:
		if not public_ip(address):_fail("web_address");return
	client=_make_client();client.read_chunk_size=4096
	client.set_http_proxy("",-1);client.set_https_proxy("",-1)
	# Fixed validated IP plus original hostname for TLS/SNI verification.
	var selected=addresses[0]
	for address in addresses:
		if not ":" in address:selected=address;break
	if client.connect_to_host(selected,443,TLSOptions.client(null,target.host))!=OK:_fail("web_connection");return
	stage="connecting";changed.emit()
static func accept_response(code,headers,length):
	if code in [301,302,303,307,308]:return {"ok":false,"status":"redirect"}
	if code!=200:return {"ok":false,"status":"http"}
	if length>MAX_BODY:return {"ok":false,"status":"size"}
	var content_type="";var seen={}
	for header in headers:
		var colon=header.find(":")
		if colon<0:continue
		var name=header.left(colon).strip_edges().to_lower();var value=header.substr(colon+1).strip_edges().to_lower()
		if name in ["content-type","content-encoding","content-length"]:
			if seen.has(name):return {"ok":false,"status":"content"}
			seen[name]=true
		if name=="content-encoding" and value!="identity":return {"ok":false,"status":"content"}
		if name=="content-type":content_type=value
	if content_type.get_slice(";",0).strip_edges() not in ["text/plain","text/html"]:return {"ok":false,"status":"content"}
	if "charset=" in content_type and content_type.get_slice("charset=",1).strip_edges().strip_edges().trim_prefix('"').trim_suffix('"') not in ["utf-8","utf8","us-ascii"]:return {"ok":false,"status":"content"}
	return {"ok":true,"content_type":content_type}
static func extract(bytes,content_type):
	if bytes.size()>MAX_BODY or 0 in bytes:return {"ok":false,"status":"content"}
	var text=bytes.get_string_from_utf8()
	if text.to_utf8_buffer()!=bytes:return {"ok":false,"status":"content"}
	if content_type.begins_with("text/html"):
		for tag in ["script","style","head","template","noscript","svg","iframe","object","form"]:
			var re=RegEx.new();re.compile('(?is)<'+tag+'\\b[^>]*>.*?(?:</'+tag+'\\s*>|$)');text=re.sub(text," ",true)
		var comments=RegEx.new();comments.compile('(?s)<!--.*?(?:-->|$)');text=comments.sub(text," ",true)
		var tags=RegEx.new();tags.compile('(?s)<[^>]*>');text=tags.sub(text,"\n",true)
		text=text.replace("&nbsp;"," ").replace("&ndash;","–").replace("&mdash;","—").replace("&hellip;","…").xml_unescape()
	var blocks=[];var count=0
	for line in text.split("\n"):
		var clean=line.strip_edges()
		if clean.is_empty():continue
		# Source is partial; never imply that a script-driven page was fully read.
		while not clean.is_empty() and blocks.size()<12:
			var fragment=clean.left(300);clean=clean.substr(fragment.length())
			blocks.append(fragment);count+=fragment.length()
		if blocks.size()>=12:break
	return {"ok":not blocks.is_empty(),"status":"empty" if blocks.is_empty() else "ok","blocks":blocks,"characters":count}
func _finish():
	var result=extract(body,str(target.get("content_type","")))
	if not result.ok:_fail("web_"+result.status);return
	result["url"]=target.url;result["retrieved_utc"]=Time.get_datetime_string_from_system(true)
	cancel();completed.emit(result)
func _fail(key):cancel();failed.emit(key)
func cancel():
	busy=false;stage="";target={};body=PackedByteArray();response_started=false;expected_length=-1
	if resolver>=0:IP.erase_resolve_item(resolver);resolver=-1
	if client!=null:client.close();client=null
	changed.emit()
func _exit_tree():cancel()
