extends RefCounted
## Bounded arithmetic grammar, never Expression.execute(), eval(), shell or model text.
var tokens=[]
var index=0
var error=""
var depth=0
var operations=0
func evaluate(raw):
	tokens=[];index=0;error="";depth=0;operations=0
	if not raw is String or raw.length()>256 or raw.strip_edges().is_empty():return {"ok":false,"status":"syntax"}
	var text=raw.replace("×","*").replace("÷","/").replace("−","-").replace("π","pi")
	var scanner=RegEx.new();scanner.compile('(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]{1,3})?|[a-zA-Z][a-zA-Z0-9]*|[()+*/^%\\-]')
	var at=0
	while at<text.length():
		if text[at] in [" ","\t"]:at+=1;continue
		var hit=scanner.search(text,at)
		if hit==null or hit.get_start()!=at:return {"ok":false,"status":"syntax"}
		tokens.append(hit.get_string().to_lower());at=hit.get_end()
		if tokens.size()>96:return {"ok":false,"status":"limit"}
	var value=expression()
	if not error.is_empty() or index!=tokens.size():return {"ok":false,"status":error if not error.is_empty() else "syntax"}
	return {"ok":true,"value":value,"text":str(value),"approximate":true}
func peek():return tokens[index] if index<tokens.size() else ""
func take():
	var value=peek();index+=1;return value
func bounded(value):
	operations+=1
	if operations>128:error="limit";return 0.0
	if not is_finite(value):error="domain";return 0.0
	return value
func expression():
	var value=term()
	while error.is_empty() and peek() in ["+","-"]:
		var op=take();var right=term();value=bounded(value+right if op=="+" else value-right)
	return value
func term():
	var value=unary()
	while error.is_empty() and peek() in ["*","/"]:
		var op=take();var right=unary()
		if op=="/" and right==0.0:error="domain";return 0.0
		value=bounded(value*right if op=="*" else value/right)
	return value
func unary():
	depth+=1
	if depth>16:error="limit";depth-=1;return 0.0
	var value=0.0
	if peek() in ["+","-"]:
		var op=take();value=unary();value=-value if op=="-" else value
	else:value=power()
	depth-=1;return value
func power():
	var value=primary()
	if peek()=="%":take();value=bounded(value/100.0)
	if peek()=="^" and error.is_empty():
		take();var exponent=unary()
		if absf(exponent)>1000 or (value==0.0 and exponent<=0.0) or (value<0.0 and exponent!=floor(exponent)):error="domain";return 0.0
		value=bounded(pow(value,exponent))
	return value
func primary():
	var token=take()
	if token=="(":
		var value=expression()
		if take()!=")":error="syntax"
		return value
	if token in ["pi","e"]:return PI if token=="pi" else exp(1.0)
	if token in ["sqrt","abs","sin","cos","ln","log10"]:
		if take()!="(":error="syntax";return 0.0
		var value=expression()
		if take()!=")":error="syntax";return 0.0
		if not error.is_empty():return 0.0
		match token:
			"sqrt":
				if value<0:error="domain";return 0.0
				return bounded(sqrt(value))
			"abs":return bounded(absf(value))
			"sin":return bounded(sin(value))
			"cos":return bounded(cos(value))
			"ln","log10":
				if value<=0:error="domain";return 0.0
				return bounded(log(value) if token=="ln" else log(value)/log(10.0))
	if not token.is_valid_float():error="syntax";return 0.0
	if "e" in token.to_lower() and absi(token.to_lower().get_slice("e",1).to_int())>308:error="domain";return 0.0
	return bounded(token.to_float())
