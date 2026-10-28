extends SceneTree
func _initialize():
 var rows=JSON.parse_string(FileAccess.get_file_as_string('res://research/quality020-cases.json'))
 var composer=preload('res://src/core/draft_composer.gd')
 for row in rows:
  if row.category in ['draft_missing','draft_given']:row['authoring_messages']=composer.messages(row.input,row.locale)
 var out=FileAccess.open(OS.get_environment('LEEMON_BENCH_FIXTURE'),FileAccess.WRITE);out.store_string(JSON.stringify(rows,'  '));out.close();quit()
