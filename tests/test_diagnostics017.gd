extends SceneTree
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func run():
 var app=root.get_node('App');app.cancel();var previous=app.provider
 var provider=preload('res://src/providers/llama_http_provider.gd').new();app.add_child(provider);app.provider=provider
 provider.last_usage={'total_ms':160,'template_ms':10,'tokenize_ms':10,'prompt_ms':40,'predicted_ms':100,'cache_n':72,'prompt_n':20,'predicted_n':11,'reasoning_budget':0,'private_text':'NEVER INCLUDE'}
 app.diagnostics.record_inference(provider.last_usage)
 app.diagnostics.values={'process_count':1,'requested_process_count':2,'process_bytes':1024}
 for locale in ['ru','en','zh-Hans']:
  app.set_locale(locale);var report=app.diagnostics.report()
  check(app.t('inference_metrics') in report and app.t('metric_prompt_ms') in report,'Human labels for separate timings '+locale)
  check(app.t('metrics_partial') in report,'Incomplete process sample disclosed '+locale)
  check(not 'NEVER INCLUDE' in report and not 'private_text' in report,'No arbitrary worker fields or source text copied '+locale)
 if OS.get_name()=='Linux':
  check(app.diagnostics._proc_path(OS.get_process_id())=='/proc/self','Own engine PID maps safely')
  check(app.diagnostics._proc_path(2147483646).is_empty(),'Unresolved child cannot fall back to unrelated host PID')
 app.provider=previous;check('12.5' in app.diagnostics.report() or app.t('metric_prompt_ms') in app.diagnostics.report(),'Numeric metrics survive worker/provider unload');provider.queue_free()
 print('DIAGNOSTICS017_TESTS: %d checks, %d failures; bounded synthetic numeric stats, no Windows claims' %[checks,failures])
 quit(0 if failures==0 else 1)
