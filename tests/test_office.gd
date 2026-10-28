extends SceneTree
const Office=preload("res://src/tools/office_patch.gd")
var checks=0
var failures=0
func _initialize():_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _run():
	var folder=OS.get_environment("LEEMON_OFFICE_FIXTURE")
	if folder.is_empty():push_error("Independent fixture required");quit(1);return
	var patch=Office.new();patch.backup_directory="user://office-test-backups"
	var path=folder.path_join("sample.docx");var original=FileAccess.get_file_as_bytes(path)
	var plan=patch.prepare(path,"Исходный текст 中文"," Новый & текст <ok> ")
	if not plan.ok:print("DOCX_PLAN_FAILURE ",plan)
	check(plan.ok and FileAccess.get_file_as_bytes(path)==original,"Real python-docx file reviewed without writing")
	if plan.get("ok",false):check(patch.commit(plan.token).ok,"Reviewed DOCX package written and verified")
	check(not patch.prepare(path,"split across","new").ok,"Cross-run text is refused rather than damaging formatting")
	check(not patch.prepare(path,"repeat","new").ok,"Repeated document text is ambiguous")
	var edited=FileAccess.get_file_as_bytes(path);plan=patch.prepare_restore()
	check(plan.ok and patch.commit(plan.token).ok and FileAccess.get_file_as_bytes(path)==original,"OOXML restore preserves exact original archive")
	var output=FileAccess.open(path,FileAccess.WRITE);output.store_buffer(edited);output.close()
	path=folder.path_join("sample.xlsx");original=FileAccess.get_file_as_bytes(path)
	plan=patch.prepare_sheet_cell(path,2,2,2,"Старое 中文","=literal text")
	if not plan.ok:print("XLSX_PLAN_FAILURE ",plan)
	check(plan.ok and FileAccess.get_file_as_bytes(path)==original,"Second worksheet resolved via workbook relationship, preview only")
	if plan.get("ok",false):check(patch.commit(plan.token).ok,"Existing XLSX text cell replaced with inert inline string")
	check(not patch.prepare_sheet_cell(path,2,99,99,"","new").ok,"Missing XLSX cell is refused")
	check(not patch.prepare_sheet_cell(path,2,2,2,"wrong","new").ok,"Stale XLSX expected value refused")
	check(not patch.prepare_sheet_cell(folder.path_join("formula.xlsx"),1,1,1,"1","2").ok,"Formula workbook rejected: no stale cached results claimed")
	check(not Office.xml_ok('<r><a></r>') and not Office.xml_ok('<!DOCTYPE r><r/>'),"Malformed XML and declarations refused")
	check(Office.address(2,27)=="AA2" and Office.address(1048576,16384)=="XFD1048576","Spreadsheet address boundaries")
	check(Office.inventory("not a zip".to_utf8_buffer()).is_empty(),"Malformed package rejected before decompression")
	check(Office.inventory(FileAccess.get_file_as_bytes(folder.path_join("bomb.zip"))).is_empty(),"Expansion bomb rejected before decompression")
	check(Office.inventory(FileAccess.get_file_as_bytes(folder.path_join("traversal.zip"))).is_empty(),"Unsafe archive entry rejected")
	print("OFFICE_TESTS: %d checks, %d failures; real OOXML packages, independent readback follows" %[checks,failures])
	quit(0 if failures==0 else 1)
