extends Node
signal sampled
var active=false
var elapsed=5.0
var values={}
var app
var last_inference={}
var previous={}
var previous_ms=0
func _ready():
	app=get_tree().root.get_node("App")
	app.desktop_actions.completed.connect(_result)
func _process(delta):
	if not active:return
	elapsed+=delta
	if elapsed<5.0:return
	elapsed=0
	values["fps"]=Engine.get_frames_per_second()
	values["fps_limit"]=Engine.max_fps
	values["engine_bytes"]=int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var pids=[OS.get_process_id()]
	if app.local_runtime.pid>0:pids.append(app.local_runtime.pid)
	values["requested_process_count"]=pids.size()
	if OS.get_name()=="Windows":app.desktop_actions.request_metrics(pids)
	elif OS.get_name()=="Linux":
		var samples=[]
		for process_id in pids:
			var path=_proc_path(process_id)
			if path.is_empty():continue
			var file=FileAccess.open(path+"/stat",FileAccess.READ)
			if not file:continue
			var text=file.get_line()
			var fields=text.substr(text.rfind(") ")+2).split(" ",false)
			file=FileAccess.open(path+"/status",FileAccess.READ)
			var memory_bytes=0
			if file:
				while not file.eof_reached():
					var line=file.get_line()
					if line.begins_with("VmRSS:"):memory_bytes=int(line.trim_prefix("VmRSS:").strip_edges().split(" ",false)[0])*1024
			# Linux CPU clock ticks are obtained once via getconf; missing values remain unknown.
			var output=[]
			if not values.has("clock_ticks"):
				if OS.execute("getconf",["CLK_TCK"],output)==0:values["clock_ticks"]=maxi(1,int(str(output[0])))
			if fields.size()>12 and values.has("clock_ticks"):
				samples.append({"pid":process_id,"bytes":memory_bytes,"cpu_seconds":float(int(fields[11])+int(fields[12]))/float(values.clock_ticks)})
		_accept(samples)
	sampled.emit()
func _result(result):
	if result.get("operation")!="metrics":return
	if result.get("status")=="ok":_accept(result.get("items",[]))
	sampled.emit()
func _accept(items):
	var now=Time.get_ticks_msec()
	var total_bytes=0
	var cpu_delta=0.0
	var comparable=previous_ms>0
	var next={}
	for item in items:
		var process_id=int(item.get("pid",0))
		var seconds=float(item.get("cpu_seconds",0))
		total_bytes+=int(item.get("bytes",0))
		if previous.has(process_id):cpu_delta+=maxf(0,seconds-float(previous[process_id]))
		else:comparable=false
		next[process_id]=seconds
	values["process_bytes"]=total_bytes
	values["process_count"]=items.size()
	values["sample_ms"]=now
	if comparable and now>previous_ms:values["cpu_percent"]=cpu_delta/(float(now-previous_ms)/1000.0)/maxi(1,OS.get_processor_count())*100.0
	else:values.erase("cpu_percent")
	previous=next;previous_ms=now
func record_inference(metrics):
	if not metrics is Dictionary:return
	var selected={}
	for key in ["total_ms","template_ms","tokenize_ms","prompt_ms","predicted_ms","cache_n","prompt_n","predicted_n","reasoning_budget"]:
		var value=metrics.get(key)
		if (value is int or value is float) and is_finite(float(value)) and value>=0:selected[key]=value
	if not selected.is_empty():last_inference=selected

func report():
	var cpu="—" if not values.has("cpu_percent") else "%.1f%%" % values.cpu_percent
	var memory="—" if int(values.get("process_count",0))==0 else "%.1f MiB" % (float(values.get("process_bytes",0))/1048576.0)
	var text=app.t("diagnostics_report",{"fps":values.get("fps",0),"limit":values.get("fps_limit",0),"memory":memory,"cpu":cpu,"processes":values.get("process_count",0),"engine":"%.1f MiB" % (float(values.get("engine_bytes",0))/1048576.0)})
	if int(values.get("process_count",0))<int(values.get("requested_process_count",0)):text+="\n"+app.t("metrics_partial")
	if not last_inference.is_empty():
		text+="\n\n"+app.t("inference_metrics")+"\n"
		for key in ["total_ms","template_ms","tokenize_ms","prompt_ms","predicted_ms","cache_n","prompt_n","predicted_n","reasoning_budget"]:
			if last_inference.has(key):text+=app.t("metric_"+key)+": "+str(last_inference[key])+"\n"

	return text

func _proc_path(process_id):
	if process_id==OS.get_process_id():return "/proc/self"
	# Container PID namespaces can expose host procfs. Inspect only our direct children.
	var stat=FileAccess.open("/proc/self/stat",FileAccess.READ)
	if stat:
		var host_pid=int(stat.get_line().split(" ")[0])
		var children=FileAccess.open("/proc/self/task/%d/children" % host_pid,FileAccess.READ)
		if children:
			for child in children.get_line().split(" ",false):
				var status=FileAccess.open("/proc/"+child+"/status",FileAccess.READ)
				if status:
					var text=status.get_line()
					while not text.is_empty():
						if text.begins_with("NSpid:") and int(text.split("\t",false)[-1])==process_id:return "/proc/"+child
						text=status.get_line()
	return "" # Never sample an unrelated host PID when namespace mapping fails.
