extends SceneTree
var reader
var finished=false
func _initialize():run.call_deferred()
func run():
	var url=OS.get_environment('LEEMON_PUBLIC_PAGE_FIXTURE')
	if url.is_empty():push_error('Explicit public fixture URL required');quit(1);return
	reader=load('res://src/tools/public_page.gd').new();root.add_child(reader)
	reader.completed.connect(func(result):
		finished=true
		print('PUBLIC_HTTPS_LIVE: PASS; verified TLS, source preserved=',result.url==url,' blocks=',result.blocks.size(),' body cleared=',reader.body.is_empty())
		quit(0))
	reader.failed.connect(func(key):finished=true;print('PUBLIC_HTTPS_LIVE: BLOCKED_OR_FAILED ',key);quit(1))
	if not reader.start(url) and not finished:quit(1)
	await create_timer(25).timeout
	if not finished:reader.cancel();push_error('Reader deadline did not finish');quit(1)
