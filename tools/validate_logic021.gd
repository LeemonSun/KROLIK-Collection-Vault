extends SceneTree
func _initialize():
 var reasoner=preload('res://src/core/logic_reasoner.gd')
 var pilot=JSON.parse_string(FileAccess.get_file_as_string('res://reports/logic021-real.json'));var rows=[];var accepted=0;var matched=0
 for row in pilot.cases:
  var result=reasoner.validate(row.raw,row.input);var direct=reasoner.direct(row.input)
  if result.get('ok',false):accepted+=1
  if result.get('verdict')==row.expected:matched+=1
  rows.append({'id':row.id,'expected':row.expected,'raw_model_validation':result,'typed_grammar_direct':direct,'initial_harness_validation':row.accepted})
 var report={'scope':'Final-source revalidation of preserved synthetic model outputs; not new inference. Earlier runningGodot cached validator before Cyrillic-case/surface fixes. Semantic format rejected; experimental model interpreter OFF by default. Directgrammar12cases is separate non-neural evidence.','cases':rows,'model_accepted':accepted,'model_verdict_matches':matched}
 var f=FileAccess.open('res://reports/logic021-final-validation.json',FileAccess.WRITE);f.store_string(JSON.stringify(report,'  '));f.close();print('FINAL_LOGIC_VALIDATION ',accepted,'accepted,',matched,'expectedverdicts;noaggregateIQ');quit()
