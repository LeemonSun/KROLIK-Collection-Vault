extends SceneTree
const Solver=preload('res://src/core/categorical_logic.gd')
const Reasoner=preload('res://src/core/logic_reasoner.gd')
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func rel(kind,a,b):return {'kind':kind,'a':a,'b':b}
func world_satisfies(world,relations):
 for row in relations:
  var exists=false
  for mask in world:
   if Solver.relation_holds(row,mask):exists=true
   elif row.kind in ['all','none']:return false
  if row.kind in ['some','some_not'] and not exists:return false
 return true
func brute(premises,conclusion):
 var sat=false;var yes=false;var no=false
 # All possible nonempty worlds over2categories (four unary types).
 for world_mask in range(1,16):
  var world=[]
  for t in range(4):
   if world_mask & (1<<t):world.append(t)
  if not world_satisfies(world,premises):continue
  sat=true
  if world_satisfies(world,[conclusion]):yes=true
  else:no=true
 return 'inconsistent' if not sat else ('entailed' if not no else ('contradicted' if not yes else 'undetermined'))
func run():
 var choices=[]
 for kind in Solver.KINDS:
  for a in range(2):
   for b in range(2):choices.append(rel(kind,a,b))
 var comparisons=0;var all_agree=true;var witnesses_valid=true
 for first in choices:
  for second in choices:
   var premises=[first,second]
   for conclusion in choices:
    var result=Solver.solve(2,premises,conclusion);comparisons+=1
    if not result.ok or result.verdict!=brute(premises,conclusion):all_agree=false
    if result.verdict in ['undetermined','contradicted'] and not world_satisfies(result.witnesses,premises+[Solver.negate(conclusion)]):witnesses_valid=false
 check(all_agree,'4096categoricalproblems match independent exhaustive world enumeration')
 check(witnesses_valid,'Every returned countermodel really satisfies premises and negated conclusion')
 var chain=[rel('all',0,1),rel('all',1,2)]
 check(Solver.solve(3,chain,rel('all',0,2)).verdict=='entailed','Universal transitivity')
 check(Solver.solve(3,[rel('all',0,1),rel('some',1,2)],rel('some',0,2)).verdict=='undetermined','Some/all entailment fallacy rejected')
 check(Solver.solve(3,[rel('all',0,1),rel('some',0,2)],rel('some',1,2)).verdict=='entailed','Existing subset witness transferred correctly')
 check(Solver.solve(2,[rel('none',0,1),rel('some',0,1)],rel('all',0,1)).verdict=='inconsistent','Inconsistent premises distinguished from factual proof')
 check(Solver.solve(2,[rel('all',0,1)],rel('some',0,1)).verdict=='undetermined','Universal premise does not create existence')
 check(Solver.solve(2,[rel('none',0,1)],rel('some',0,1)).verdict=='contradicted','Contradicted distinguished from unknown')
 for row in [rel('invalid',0,1),rel('all',-1,1),rel('all',0.5,1),{'kind':'all','a':0,'b':1,'extra':true},null]:
  check(not Solver.solve(2,[row],rel('all',0,1)).ok,'Malformed relation rejected')
 check(not Solver.solve(7,chain,rel('all',0,2)).ok and not Solver.solve(2,[],rel('all',0,1)).ok,'Bounded solver inputs')
 for q in ['Все зоры синие. Некоторые синие вещи круглые. Следует ли, что некоторые зоры круглые?','All zors are blue. Some blue things are round. Does it follow that some zors are round?','所有佐尔都是蓝色的。有些蓝色物体是圆的。能否推出有些佐尔是圆的？']:
  check(Reasoner.requested(q),'Generic categorical argument detected across languages')
 for q in ['Как дела?','Какая погода?','Докажи теорему Ферма','All games should work','Некоторые любят чай. Что думаешь?','This sentence is false. True or false?']:
  check(not Reasoner.requested(q),'Unsupported/general requests remain ordinary model tasks')
 var question='All zors are blue. Some blue things are round. Does it follow that some zors are round?'
 var proposal={'premises':[{'kind':'all','subject':'zors','predicate':'blue','quote':'All zors are blue.'},{'kind':'some','subject':'blue','predicate':'round','quote':'Some blue things are round.'}],'conclusion':{'kind':'some','subject':'zors','predicate':'round'}}
 check(not Reasoner.clauses('Все зоры синие. Некоторые синие вещи круглые. Следует ли, что некоторые зоры круглые?').is_empty(),'Cyrillic capitalized inference marker parsed')
 var result=Reasoner.validate(JSON.stringify(proposal),question)
 check(result.get('verdict')=='undetermined','Exact source-backed formalization reaches deterministic solver')
 for locale in ['ru','en','zh-Hans']:
  var text=Reasoner.format_result(result,locale);check('zors' in text and 'blue' in text and not '{' in text,'Human-readable interpretation, no JSON '+locale)
 var invalid=proposal.duplicate(true);invalid.premises[0].quote='Invented premise.'
 check(not Reasoner.validate(JSON.stringify(invalid),question).ok,'Invented premise witness rejected')
 invalid=proposal.duplicate(true);invalid.premises[0].subject='dragons'
 check(not Reasoner.validate(JSON.stringify(invalid),question).ok,'Invented category rejected')
 invalid=proposal.duplicate(true);invalid.premises[0].subject='round'
 check(not Reasoner.validate(JSON.stringify(invalid),question).ok,'Category not in cited sentence rejected')
 invalid=proposal.duplicate(true);invalid.premises=[]
 check(not Reasoner.validate(JSON.stringify(invalid),question).ok,'Unsupported abstention never generates a verdict')
 # Explicit limitation: source presence cannot verify quantifier meaning.
 invalid=proposal.duplicate(true);invalid.premises[0].kind='none'
 check(not Reasoner.validate(JSON.stringify(invalid),question).ok,'Independent quantifier witness rejects wrong relation polarity')
 check(not Reasoner.surface_relation('Some zors probably are blue.','zors','blue'),'Modality cannot be silently converted to certainty')
 check(not Reasoner.surface_relation('All bright red robots are devices.','robots','devices'),'Dropped subject modifiers rejected')
 check(not Reasoner.surface_relation('Some zors admire blue.','zors','blue'),'Relational verbs outside unary-set scope rejected')
 check(Reasoner.surface_relation('All bright red robots are devices.','bright red robots','devices'),'Literal complete multiword category retained')
 var pilot=JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir().path_join('fixtures/logic021-cases.json')))
 var pilot_ok=true
 for spec in pilot:
  if Reasoner.direct(spec.input).get('verdict')!=spec.expected:pilot_ok=false
 check(pilot_ok,'12typedargumentfixtures across3languages handled without model')
 for ambiguous in ['Все большие красные роботы маленькие устройства. Некоторые устройства красные. Следует ли, что некоторые роботы красные?','All birds probably are animals. Some animals are blue. Does it follow that some birds are blue?']:
  check(not Reasoner.direct(ambiguous).get('ok',false),'Unknown or modal grammar not guessed')
 var language_ok=true;var parsed_cases=0
 for locale in ['ru','en','zh-Hans']:
  var names={'ru':['альфы','беты','гаммы'],'en':['alphas','betas','gammas'],'zh-Hans':['甲类','乙类','丙类']}[locale]
  var patterns={'ru':{'all':'Все %s %s','none':'Никакие %s не %s','some':'Некоторые %s %s','some_not':'Некоторые %s не %s'},'en':{'all':'All %s are %s','none':'No %s are %s','some':'Some %s are %s','some_not':'Some %s are not %s'},'zh-Hans':{'all':'所有%s都是%s','none':'没有%s是%s','some':'有些%s是%s','some_not':'有些%s不是%s'}}[locale]
  var pairs=[[0,1],[1,2],[2,0],[0,0]]
  for first in pairs:
   for second in pairs:
    for existential in ['some','some_not']:
     for kind in Solver.KINDS:
      for last in pairs:
       var premises=[rel('all',first[0],first[1]),rel(existential,second[0],second[1])];var conclusion=rel(kind,last[0],last[1]);var lines=[]
       for row in premises:lines.append(patterns[row.kind] % [names[row.a],names[row.b]])
       var q='。'.join(lines)+'。能否推出'+(patterns[kind] % [names[last[0]],names[last[1]]])+'？' if locale=='zh-Hans' else '. '.join(lines)+'. '+('Следует ли, что ' if locale=='ru' else 'Does it follow that ')+(patterns[kind] % [names[last[0]],names[last[1]]])+'?'
       var parsed=Reasoner.direct(q);var expected=Solver.solve(3,premises,conclusion);parsed_cases+=1
       if parsed.get('verdict')!=expected.verdict:language_ok=false
 check(language_ok,'1536newgrammararguments across3languages match independently verified solver')
 print('LANGUAGE_GRAMMAR021 ',parsed_cases,' synthetic cases')
 print('LOGIC021: %dchecks, %dfailures; %dindependent exhaustive comparisons; model interpretation not proven' %[checks,failures,comparisons]);quit(0 if failures==0 else 1)
