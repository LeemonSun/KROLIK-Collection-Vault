/* Local orchestration for functions.exec. Read this file, eval it, then call
   await companionResume({action:'bootstrap'|'assets'|'checkpoint', root?:...}).
   GitHub stores sources only. No Actions, remote builds, models or credentials. */
globalThis.companionResume = async function(options = {}) {
  const repo = 'LeemonSun/KROLIK-Collection-Vault';
  const api = 'https://api.github.com/repos/' + repo;
  const quote = s => "'" + s.replaceAll("'", "'\\''") + "'";
  const check = r => {if (r.isError) throw Error(JSON.stringify(r.content));return r.structuredContent;};
  const get = async url => JSON.parse(check(await tools.mcp__codex_apps__github_fetch({url})).content);
  const file = async (path,ref) => check(await tools.mcp__codex_apps__github_fetch_file({repository_full_name:repo,path,ref})).content;
  const cwd = (await tools.exec_command({cmd:'pwd',max_output_tokens:1000})).output.trim();
  const root = options.root || (cwd.endsWith('/companion-foundation') ? cwd : cwd + '/companion-foundation');
  async function py(code,payload={}) {
    const encoded=JSON.stringify({...payload,root});
    let input='json.loads('+JSON.stringify(encoded)+')';
    let temporary;
    if(encoded.length>40000) {
      temporary='/tmp/companion-resume-'+Date.now()+'-'+Math.random().toString(16).slice(2)+'.json';
      await tools.apply_patch('*** Begin Patch\n*** Add File: '+temporary+'\n+'+encoded+'\n*** End Patch');
      input='json.loads(pathlib.Path('+JSON.stringify(temporary)+').read_text())';
    }
    const cmd = "python3 - <<'COMPANION_RESUME_PY'\nimport json, pathlib, sys\np=" + input + "\nroot=pathlib.Path(p['root'])\n" + code + '\nCOMPANION_RESUME_PY';
    let r = await tools.exec_command({cmd,max_output_tokens:250000,yield_time_ms:1000});
    let output=r.output;
    while(r.session_id) {r=await tools.write_stdin({session_id:r.session_id,chars:'',yield_time_ms:1000,max_output_tokens:250000});output+=r.output;}
    if(temporary) await tools.exec_command({cmd:'rm -- '+quote(temporary),max_output_tokens:1000});
    if(r.exit_code!==0) throw Error(output);
    return JSON.parse(output);
  }
  const head = (await get(api+'/git/ref/heads/main')).object.sha;
  const action=options.action || 'bootstrap';
  if(action==='bootstrap') {
    const index=JSON.parse(await file('recovery/index.json',head));
    const local=await py("f=root/'recovery/index.json'\nprint(json.dumps(json.loads(f.read_text()) if f.exists() else {}))");
    let result={written:[],conflicts:[]};
    const warm=local.content_id===index.content_id && await py("print(json.dumps(all((root/name).is_file() for name in p['names'])))",{names:Object.keys(index.files)});
    if(!warm) {
      let capsule;
      if(index.capsule_parts){
        if(index.capsule_parts.length>128)throw Error('Capsule part bounds');
        const parts=[];
        for(const part of index.capsule_parts){
          if(!/^recovery\/source_capsule\.\d{3}\.b64$/.test(part))throw Error('Unsafe capsule part');
          parts.push((await file(part,head)).trim());
        }
        capsule=parts.join('');
      }else capsule=await file(index.capsule_path,head);
      result=await py(`import base64, hashlib, io, zipfile, tempfile, importlib.util
raw=base64.b64decode(p['capsule'],validate=False)
if hashlib.sha256(raw).hexdigest()!=p['index']['capsule_sha256']:raise ValueError('Capsule SHA mismatch')
with zipfile.ZipFile(io.BytesIO(raw)) as z:
 helper=z.read('tools/resume.py'); known=json.loads(z.read('recovery/known_sources.json'))
with tempfile.TemporaryDirectory() as td:
 helper_path=pathlib.Path(td)/'resume.py';helper_path.write_bytes(helper)
 spec=importlib.util.spec_from_file_location('companion_resume',helper_path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 result=module.restore(root,raw,p['index']['capsule_sha256'],known)
(root/'recovery/index.json').write_text(json.dumps(p['index'],indent=2)+'\\n')
(root/'recovery/source_capsule.b64').write_text(p['capsule'])
print(json.dumps(result))`,{capsule,index});
    }
    // Capsule-specific recovery layer after an execution-environment outage.
    // A later normal checkpoint changes content_id and makes this layer inactive.
    const overlay = JSON.parse(await file('recovery/pending-overlay.json',head));
    if(overlay.base_content_id===index.content_id) {
      const entries=[];
      for(const entry of overlay.files) entries.push({...entry,content:await file(entry.path,head)});
      const patched=await py("import hashlib\ndef gitsha(data):return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\\0'+data).hexdigest()\nwritten=[];conflicts=[]\nfor item in p['entries']:\n name=item['path'];path=root/name\n if pathlib.Path(name).is_absolute() or '..' in pathlib.Path(name).parts or not path.resolve().is_relative_to(root.resolve()):raise ValueError('Unsafe overlay path')\n data=item['content'].encode('utf-8')\n if gitsha(data)!=item['sha']:raise ValueError('Overlay source SHA mismatch: '+name)\n current=gitsha(path.read_bytes()) if path.is_file() else None\n if current==item['sha']:continue\n if current!=item.get('base_sha'):conflicts.append(name);continue\n path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data);written.append(name)\n(root/'recovery/pending-overlay.json').write_text(json.dumps(p['overlay'],indent=2)+'\\n')\nprint(json.dumps({'written':written,'conflicts':conflicts}))",{entries,overlay});
      result.written.push(...patched.written);result.conflicts.push(...patched.conflicts);
    }
    const retirement=await py("sys.path.insert(0,str(root/'tools'))\nimport resume\nf=root/'recovery/retired_paths.json'\nprint(json.dumps(resume.retire(root,json.loads(f.read_text()).get('files',[])) if f.exists() else {'retired':[],'conflicts':[]}))");
    result.conflicts.push(...retirement.conflicts);
    await py("f=root/'.resume-remote.json'\nf.write_text(json.dumps({'head':p['head'],'files':p['files']})+'\\n')\nprint(json.dumps({'saved':True}))",{head,files:index.files});
    const state=await tools.exec_command({cmd:'python3 '+quote(root+'/tools/resume.py')+' status',max_output_tokens:4000});
    if(state.exit_code!==0)throw Error(state.output);
    return {head,warm,written:result.written.length,retired:retirement.retired.length,conflicts:result.conflicts,status:JSON.parse(state.output)};
  }
  if(action==='assets') {
    const plan=await py("sys.path.insert(0,str(root/'tools'))\nimport resume\nprint(json.dumps(resume.asset_plan(root,p['group'])))",{group:options.group||'runtime'});
    const result={downloaded:[],preserved:[]};
    // Fresh directory URLs per file; do not store signed URLs in receipts or logs.
    for(const entry of plan.missing) {
      const exists=await py("print(json.dumps((root/p['path']).exists()))",entry);
      if(exists){result.preserved.push(entry.path);continue;}
      let url=entry.url;
      if(!url){
        const parent=entry.path.includes('/')?entry.path.slice(0,entry.path.lastIndexOf('/')):'';
        const listing=await get(api+'/contents/'+parent+'?ref='+head);
        url=listing.find(x=>x.path===entry.path)?.download_url;
      }
      if(!url)throw Error('Missing download URL for '+entry.path);
      await py(`import urllib.request, hashlib, os, tempfile
path=root/p['path'];path.parent.mkdir(parents=True,exist_ok=True)
with tempfile.NamedTemporaryFile(dir=path.parent,delete=False) as f:
 temp=pathlib.Path(f.name)
try:
 with urllib.request.urlopen(p['url'],timeout=45) as response, temp.open('wb') as output:
  while block:=response.read(1024*1024):output.write(block)
 if temp.stat().st_size!=p['bytes'] or hashlib.sha256(temp.read_bytes()).hexdigest()!=p['sha256']:raise ValueError('Asset hash mismatch')
 if path.exists():raise ValueError('Asset appeared during download; preserved')
 os.replace(temp,path)
finally:
 if temp.exists():temp.unlink()
print(json.dumps({'verified':p['path']}))`,{...entry,url});
      result.downloaded.push(entry.path);
    }
    return result;
  }
  if(action==='checkpoint') {
    const receipt=await py("f=root/'.resume-remote.json'\nprint(json.dumps(json.loads(f.read_text()) if f.exists() else {}))");
    const expected=options.expected_head||receipt.head;
    if(!expected||head!==expected)throw Error('Remote changed or bootstrap required; inspect head '+head+' before checkpoint');
    const payload=await py(`sys.path.insert(0,str(root/'tools'))
import resume
summary=resume.make_capsule(root)
entries=resume.source_entries(root)
for name in ['recovery/index.json',*summary.get('capsule_parts',[summary['capsule_path']])]:entries[name]=(root/name).read_bytes()
print(json.dumps({'summary':summary,'entries':{name:{'bytes':len(data),'sha':resume.gitsha(data)} for name,data in entries.items()}}))`);
    const commit=await get(api+'/git/commits/'+head);
    const tree=await get(api+'/git/trees/'+commit.tree.sha+'?recursive=1');
    if(tree.truncated)throw Error('Tree truncated; stop without overwriting');
    const old=Object.fromEntries(tree.tree.filter(x=>x.type==='blob').map(x=>[x.path,x.sha]));
    const changed=Object.entries(payload.entries).filter(([path,v])=>old[path]!==v.sha);
    const retired=await py("f=root/'recovery/retired_paths.json'\nprint(json.dumps(json.loads(f.read_text()).get('files',[]) if f.exists() else []))");
    const removed=retired.filter(entry=>old[entry.path]);
    for(const entry of removed) {
      if(old[entry.path]!==entry.gitsha || payload.entries[entry.path])throw Error('Retirement conflict: '+entry.path);
    }
    // Remove superseded generated capsules; keep only the index-selected format.
    for(const path of Object.keys(old)) {
      if(/^recovery\/source_capsule(?:\.\d{3})?\.b64$/.test(path) && !payload.entries[path])removed.push({path,gitsha:old[path]});
    }
    if(!changed.length&&!removed.length)return {head,changed:0,deleted:0,...payload.summary};
    const elements=[];
    for(const [path,v] of changed) {
      if(v.bytes>600000)throw Error('Text checkpoint entry too large: '+path);
      const content=await py("print(json.dumps((root/p['path']).read_text()))",{path});
      elements.push({path,type:'blob',mode:'100644',content});
    }
    for(const entry of removed)elements.push({path:entry.path,type:'blob',mode:'100644',sha:null});
    const nextTree=check(await tools.mcp__codex_apps__github_create_tree({repository_full_name:repo,base_tree_sha:commit.tree.sha,tree_elements:elements}));
    const next=check(await tools.mcp__codex_apps__github_create_commit({repository_full_name:repo,parent_sha:head,tree_sha:nextTree.sha,message:options.message||'Store local development checkpoint [skip ci]'}));
    check(await tools.mcp__codex_apps__github_update_ref({repository_full_name:repo,branch_name:'main',expected_sha:head,sha:next.sha,force:false}));
    const verified=(await get(api+'/git/ref/heads/main')).object.sha;
    if(verified!==next.sha)throw Error('Checkpoint head verification failed');
    await py("(root/'.resume-remote.json').write_text(json.dumps({'head':p['head']})+'\\n')\nprint(json.dumps({'saved':True}))",{head:next.sha});
    return {head:next.sha,changed:changed.length,deleted:removed.length,...payload.summary};
  }
  throw Error('Unknown resume action: '+action);
};
