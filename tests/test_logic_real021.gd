extends SceneTree
const Reasoner=preload('res://src/core/logic_reasoner.gd')
var output=''
var rows=[]
func _initialize():run.call_deferred()
func run():
 var provider=preload('res://src/providers/llama_http_provider.gd').new();root.add_child(provider)
 provider.configure_local(int(OS.get_environment('LEEMON_TEST_PORT')),OS.get_environment('LEEMON_TEST_TOKEN'))
 provider.completed.connect(func(value):output=value);provider.failed.connect(func(key):output='ERROR:'+key)
 var fixtures=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/logic021-cases.json'))
 for spec in fixtures:
  var now=Time.get_ticks_msec();var ctx=Reasoner.prepare(spec.input);output=''
  provider.submit(ctx.messages,{'max_tokens':384,'context_tokens':2048,'response_schema':ctx.schema,'seed':42})
  var deadline=Time.get_ticks_msec()+85000
  while output.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
  var accepted=Reasoner.validate(output,spec.input)
  var row={'id':spec.id,'locale':spec.locale,'input':spec.input,'expected':spec.expected,'raw':output,'truncated':provider.last_truncated,'accepted':accepted,'usage':provider.last_usage,'elapsed_ms':Time.get_ticks_msec()-now}
  row['verdict_match']=accepted.get('ok',false) and accepted.get('verdict')==spec.expected
  rows.append(row)
  var f=FileAccess.open(OS.get_environment('LEEMON_REAL_REPORT'),FileAccess.WRITE);f.store_string(JSON.stringify({'scope':'synthetic actualGodotHTTP+pinned2B categorical formalization; noOS; verdictmatch not semantic interpretation proof','cases':rows},'  '));f.close()
  print('REAL_LOGIC021 ',JSON.stringify(row))
 provider.cancel();provider.queue_free();print('LOGIC021_DONE ',rows.size(),' real generations; manualformalizationreviewrequired');quit(0)
