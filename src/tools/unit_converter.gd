extends RefCounted
## Canonical units, dimensions and affine temperature conversion; no inference.
const UNITS={
	"mm":["length",0.001,0.0],"cm":["length",0.01,0.0],"m":["length",1.0,0.0],"km":["length",1000.0,0.0],"in":["length",0.0254,0.0],"ft":["length",0.3048,0.0],"mi":["length",1609.344,0.0],
	"mg":["mass",0.000001,0.0],"g":["mass",0.001,0.0],"kg":["mass",1.0,0.0],"lb":["mass",0.45359237,0.0],
	"ms":["time",0.001,0.0],"s":["time",1.0,0.0],"min":["time",60.0,0.0],"h":["time",3600.0,0.0],"day":["time",86400.0,0.0],
	"ml":["volume",0.000001,0.0],"l":["volume",0.001,0.0],"m3":["volume",1.0,0.0],
	"B":["data",1.0,0.0],"KB":["data",1000.0,0.0],"MB":["data",1000000.0,0.0],"GB":["data",1000000000.0,0.0],"KiB":["data",1024.0,0.0],"MiB":["data",1048576.0,0.0],"GiB":["data",1073741824.0,0.0],
	"C":["temperature",1.0,273.15],"F":["temperature",0.5555555555555556,255.3722222222222],"K":["temperature",1.0,0.0],
	"Pa":["pressure",1.0,0.0],"kPa":["pressure",1000.0,0.0],"bar":["pressure",100000.0,0.0],
	"m/s":["speed",1.0,0.0],"km/h":["speed",0.2777777777777778,0.0]}
const ALIASES={"мм":"mm","см":"cm","м":"m","км":"km","мг":"mg","г":"g","кг":"kg","мс":"ms","с":"s","мин":"min","ч":"h","день":"day","мл":"ml","л":"l","м³":"m3","м3":"m3","байт":"B","КБ":"KB","МБ":"MB","ГБ":"GB","°C":"C","°F":"F","Па":"Pa","кПа":"kPa","бар":"bar","м/с":"m/s","км/ч":"km/h","米":"m","厘米":"cm","毫米":"mm","千米":"km","克":"g","千克":"kg","秒":"s","分钟":"min","小时":"h","升":"l","毫升":"ml","摄氏度":"C","华氏度":"F","开尔文":"K"}
static func convert(number,from_unit,to_unit):
	if not number is String or number.length()>64 or not number.is_valid_float():return {"ok":false,"status":"syntax"}
	var from_=str(ALIASES.get(from_unit,from_unit));var to=str(ALIASES.get(to_unit,to_unit))
	if not UNITS.has(from_) or not UNITS.has(to) or UNITS[from_][0]!=UNITS[to][0]:return {"ok":false,"status":"units"}
	if "e" in number.to_lower() and absi(number.to_lower().get_slice("e",1).to_int())>308:return {"ok":false,"status":"domain"}
	var n=number.to_float();var a=UNITS[from_];var b=UNITS[to];var base=n*a[1]+a[2]
	if not is_finite(n) or not is_finite(base) or (a[0]=="temperature" and base<0.0):return {"ok":false,"status":"domain"}
	var result=(base-b[2])/b[1]
	if not is_finite(result):return {"ok":false,"status":"domain"}
	return {"ok":true,"text":str(result),"from":from_,"to":to,"value":result}
