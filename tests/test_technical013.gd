extends SceneTree
const Doc=preload("res://src/tools/docx_text.gd")
const Office=preload("res://src/tools/office_patch.gd")
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func document(body):return '<w:document><w:body>'+body+'</w:body></w:document>'
func run():
	var plain='<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>abЖ</w:t></w:r><w:r><w:rPr><w:i/></w:rPr><w:t>中文cd</w:t></w:r></w:p>'
	var result=Doc.plan(document(plain),'bЖ中文c',' &新 ')
	check(result.ok and 'a &amp;新 ' in result.xml and '>d</w:t>' in result.xml,'Cross-run Unicode, entity escaping and outside text survive')
	check(result.ok and '<w:b/>' in result.xml and '<w:i/>' in result.xml,'Both original run property blocks retained')
	check(result.ok and result.xml.count('xml:space="preserve"')==2,'Boundary whitespace preservation on modified runs')
	check(not Doc.plan(document('<w:p><w:r><w:t>aaa</w:t></w:r></w:p>'),'aa','x').ok,'Overlapping matches refused')
	check(not Doc.plan(document(plain+plain),'Ж中文','x').ok,'Duplicate cross-run matches refused')
	check(not Doc.plan(document('<w:p><w:r><w:t>ab</w:t></w:r></w:p><w:p><w:r><w:t>cd</w:t></w:r></w:p>'),'bc','x').ok,'Paragraph boundary never silently concatenated')
	for boundary in ['<w:tab/>','<w:br/>','<w:fldChar w:fldCharType="begin"/>','<w:bookmarkStart w:id="1"/>','<w:drawing/>','<w:instrText>code</w:instrText>']:
		check(not Doc.plan(document('<w:p><w:r><w:t>ab</w:t>'+boundary+'<w:t>cd</w:t></w:r></w:p>'),'bc','x').ok,'Unsupported structure refused: '+boundary)
	check(not Doc.plan(document('<w:p><w:hyperlink><w:r><w:t>abc</w:t></w:r></w:hyperlink></w:p>'),'abc','x').ok,'Hyperlink target is not rewritten')
	check(not Doc.plan(document('<w:p><w:r><w:rPr><w:vanish/></w:rPr><w:t>abc</w:t></w:r></w:p>'),'abc','x').ok,'Directly hidden run refused')
	var profiles=preload("res://src/core/profile.gd").new()
	var quiet=profiles.effective('quality','quiet');var standard=profiles.effective('quality','standard')
	check(quiet.cpu_threads==1 and quiet.batch_tokens==32 and quiet.idle_unload_seconds==30,'Quiet compute budget applies across quality profiles')
	check(standard.cpu_threads==4 and standard.batch_tokens==128 and standard.idle_unload_seconds==180,'Standard profile retains former budget')
	check(profiles.config('quality').cpu_threads==4,'Effective budget does not mutate profile definitions')
	var worker=preload("res://src/runtime/local_runtime.gd").new();worker.manifest={"model":{"file":"fixture.gguf"}}
	var args=worker.build_args(quiet,16)
	check(args[args.find('--threads')+1]=='1' and args[args.find('--threads-batch')+1]=='1','Both generation and prompt processing honor thread budget')
	check(args[args.find('--batch-size')+1]=='32' and args[args.find('--ubatch-size')+1]=='32','Both batching arguments honor budget')
	check(args[args.find('--parallel')+1]=='1' and args[args.find('--poll')+1]=='0','Single inference slot and no busy polling preserved')
	worker.free()
	var transcriber=preload("res://src/tools/whisper_transcriber.gd").new();transcriber.manifest={"model":{"file":"fixture.bin"}};transcriber.cpu_thread_limit=1
	args=transcriber.build_asr_args("input.wav","output","ru",16)
	check(args[args.find("-t")+1]=='1','Quiet budget applies to speech inference too')
	transcriber.free()

	var folder=ProjectSettings.globalize_path('user://technical013');DirAccess.make_dir_recursive_absolute(folder)
	var path=folder.path_join('range.csv');var original='name,value\nA,1.25\nB,-2\nC,4.75\nD,=100\nE,true\nF,\n'.to_utf8_buffer()
	var file=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(original);file.close()
	var engine=Office.new();var summary=engine.inspect_range(path,1,2,2,7,2)
	check(summary.ok and summary.count==3 and summary.blank==1 and summary.other==2 and is_equal_approx(summary.sum,4.0),'CSV summary uses data rather than model arithmetic; formulas excluded')
	check(summary.ok and is_equal_approx(summary.mean,4.0/3.0) and summary.min==-2.0 and summary.max==4.75,'Range mean and extrema')
	check(FileAccess.get_file_as_bytes(path)==original and engine.pending.is_empty(),'Summary creates no approval authority and never writes source')
	var app=root.get_node('App');app.cancel();app.application_access.target={}
	app.resource_mode='standard';app.set_resource_mode('quiet')
	check(app.resource_mode=='quiet' and app.runtime_options().cpu_threads==1 and app.local_runtime.pid==-1,'App mode change stops owned worker and propagates options')
	app.set_resource_mode('foreign');check(app.resource_mode=='quiet','Unknown mode ignored')
	for locale in ['ru','en','zh-Hans']:
		app.set_locale(locale)
		for key in ['resource_mode','resource_hint','office_type_number','file_status_office_value','range_result','range_hint']:check(app.t(key)!=key,'Localized technical controls: '+locale+'/'+key)
	print('TECHNICAL013_TESTS: %d checks, %d failures; no model quality or Windows claim' %[checks,failures])
	quit(0 if failures==0 else 1)
