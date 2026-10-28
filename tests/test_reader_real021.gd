extends SceneTree
const Reader=preload('res://src/core/window_reader.gd')
const Baseline=preload('res://tests/fixtures/window_reader020.gd')
var output=''
var rows=[]
func _initialize():run.call_deferred()
func identity():return {'handle':'123','target_pid':234,'started':'345','title':'Synthetic evidence','app':'Unknown'}
func run():
 var provider=preload('res://src/providers/llama_http_provider.gd').new();root.add_child(provider)
 provider.configure_local(int(OS.get_environment('LEEMON_TEST_PORT')),OS.get_environment('LEEMON_TEST_TOKEN'))
 provider.completed.connect(func(value):output=value);provider.failed.connect(func(key):output='ERROR:'+key)
 var fixtures=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/reader021-cases.json'))
 for variant in ['baseline020','current021']:
  var reader=Baseline.new() if variant=='baseline020' else Reader.new()
  for spec in fixtures:
   var now=Time.get_ticks_msec();var ctx=reader.prepare(spec.question,identity(),spec.blocks,now,spec.locale);output=''
   if not ctx.get('ok',false):push_error('Invalid fixture context');quit(1);return
   provider.submit(ctx.messages,{'max_tokens':256,'context_tokens':2048,'response_schema':ctx.schema,'seed':42})
   var deadline=Time.get_ticks_msec()+85000
   while output.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
   var accepted=reader.validate(output,ctx,identity(),Time.get_ticks_msec())
   var row={'id':spec.id,'variant':variant,'locale':spec.locale,'question':spec.question,'expected':spec.expected,'expected_insufficient':spec.insufficient,'selected_expected_evidence':JSON.stringify(ctx.map).contains(spec.evidence_marker) if not spec.evidence_marker.is_empty() else null,'raw':output,'truncated':provider.last_truncated,'accepted':accepted,'usage':provider.last_usage,'elapsed_ms':Time.get_ticks_msec()-now}
   # Literal match is an aid only: manual entailment review stays separate.
   row['expected_literal_present']=spec.expected in str(accepted.get('answer','')) if not spec.expected.is_empty() else null
   if variant=='current021' and not accepted.get('ok',false):row['fallback']=reader.fallback(ctx,identity(),Time.get_ticks_msec())
   rows.append(row)
   var f=FileAccess.open(OS.get_environment('LEEMON_REAL_REPORT'),FileAccess.WRITE);f.store_string(JSON.stringify({'scope':'synthetic real pinned2B generation via actual Godot HTTP adapter; no Windows; seed42; finite sample; raw failures retained','cases':rows},'  '));f.close()
   print('REAL_READER021 ',JSON.stringify(row))
 provider.cancel();provider.queue_free();print('READER021_DONE ',rows.size(),' real generations; not all semantic passes');quit(0)
