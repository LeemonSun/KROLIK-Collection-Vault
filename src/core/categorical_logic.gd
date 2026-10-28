extends RefCounted
## Complete finite-type decision procedure for bounded unary categorical statements.
## Not arbitrary first-order logic, self-reference, causal inference or real-world fact verification.
const KINDS=['all','none','some','some_not']
const MAX_CLASSES=6
const MAX_PREMISES=8
static func relation_holds(row,mask):
 var a=(mask & (1<<int(row.a)))!=0;var b=(mask & (1<<int(row.b)))!=0
 match row.kind:
  'all':return not a or b
  'none':return not(a and b)
  'some':return a and b
  'some_not':return a and not b
 return false
static func negate(row):
 return {'kind':{'all':'some_not','none':'some','some':'none','some_not':'all'}[row.kind],'a':row.a,'b':row.b}
static func valid_relation(row,count):
 if not row is Dictionary or row.size()!=3 or row.get('kind') not in KINDS:return false
 for key in ['a','b']:
  var value=row.get(key)
  if not (value is int or value is float) or float(value)!=floor(float(value)) or value<0 or value>=count:return false
 return true
static func model(count,relations):
 var types=[]
 for mask in range(1<<count):
  var allowed=true
  for row in relations:
   if row.kind in ['all','none'] and not relation_holds(row,mask):allowed=false;break
  if allowed:types.append(mask)
 if types.is_empty():return {'sat':false}
 var witnesses=[]
 for row in relations:
  if row.kind not in ['some','some_not']:continue
  var found=-1
  for mask in types:
   if relation_holds(row,mask):found=mask;break
  if found<0:return {'sat':false}
  if found not in witnesses:witnesses.append(found)
 # Domain nonempty; classes may all be empty (no implicit existential import).
 if witnesses.is_empty():witnesses.append(types[0])
 return {'sat':true,'witnesses':witnesses}
static func solve(count,premises,conclusion):
 if not count is int or count<1 or count>MAX_CLASSES or not premises is Array or premises.is_empty() or premises.size()>MAX_PREMISES:return {'ok':false}
 for row in premises:
  if not valid_relation(row,count):return {'ok':false}
 if not valid_relation(conclusion,count):return {'ok':false}
 var prior=model(count,premises)
 if not prior.sat:return {'ok':true,'verdict':'inconsistent','witnesses':[]}
 var with_not=premises.duplicate(true);with_not.append(negate(conclusion));var counter=model(count,with_not)
 if not counter.sat:return {'ok':true,'verdict':'entailed','witnesses':prior.witnesses}
 var with_yes=premises.duplicate(true);with_yes.append(conclusion)
 return {'ok':true,'verdict':'undetermined' if model(count,with_yes).sat else 'contradicted','witnesses':counter.witnesses}
