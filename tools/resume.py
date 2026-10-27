#!/usr/bin/env python3
"""Small, offline project handoff. Never downloads models or changes unknown local edits."""
import argparse,base64,hashlib,io,json,os,tempfile,zipfile
from pathlib import Path,PurePosixPath
ROOT=Path(__file__).resolve().parents[1]
MAX_BYTES=32*1024*1024
SKIP={'.git','.godot','build','dist','__pycache__','userdata','captures','secrets','downloads'}
BINARY={'.png','.jpg','.jpeg','.webp','.otf','.ttf','.zip','.gguf','.onnx','.safetensors','.exe','.dll','.bin','.pyc','.log','.tmp'}
GENERATED={'recovery/source_capsule.b64','recovery/index.json','reports/resume_tests.txt'}
def sha(data):return hashlib.sha256(data).hexdigest()
def gitsha(data):return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
def safe_path(root,relative):
 p=PurePosixPath(relative)
 if not relative or not p.parts or '\\' in relative or p.is_absolute() or '..' in p.parts or ':' in p.parts[0] or '.git' in p.parts:raise ValueError('Unsafe path: '+relative)
 target=root.joinpath(*p.parts)
 if not target.resolve().is_relative_to(root.resolve()) or target.is_symlink():raise ValueError('Path escapes workspace: '+relative)
 return target

def source_entries(root):
 out={}
 for p in sorted(root.rglob('*')):
  rel=p.relative_to(root);name=rel.as_posix()
  if not p.is_file() or p.is_symlink() or name in GENERATED or name.startswith("recovery/source_capsule.") or any(x in SKIP for x in rel.parts):continue
  if any(x.startswith('.') and x not in {'.gitignore','.gitattributes','.gdignore'} for x in rel.parts):continue
  if p.suffix.lower() in BINARY or p.name.startswith('.env') or p.name=='export_credentials.cfg':continue
  data=p.read_bytes()
  try:data.decode('utf-8')
  except UnicodeDecodeError:continue
  out[name]=data
 return out

def make_capsule(root):
 entries=source_entries(root)
 meta={name:{'sha256':sha(data),'gitsha':gitsha(data),'bytes':len(data)} for name,data in entries.items()}
 content_id=sha(json.dumps(meta,sort_keys=True,separators=(',',':')).encode())
 buffer=io.BytesIO()
 with zipfile.ZipFile(buffer,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
  for name,data in {**entries,'_CAPSULE_INDEX.json':json.dumps({'schema_version':1,'content_id':content_id,'files':meta},sort_keys=True).encode()}.items():
   info=zipfile.ZipInfo(name,(2026,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16;archive.writestr(info,data)
 data=buffer.getvalue();encoded=base64.b64encode(data).decode()
 target=root/'recovery';target.mkdir(exist_ok=True)
 (target/'source_capsule.b64').write_text(encoded+'\n')
 index={'schema_version':1,'repository':'LeemonSun/KROLIK-Collection-Vault','branch':'main','content_id':content_id,'capsule_sha256':sha(data),'capsule_bytes':len(data),'source_files':len(entries),'capsule_path':'recovery/source_capsule.b64','files':meta}
 if len(encoded)>500000:
  parts=[]
  for offset in range(0,len(encoded),400000):
   name='recovery/source_capsule.%03d.b64' % (offset//400000)
   (root/name).write_text(encoded[offset:offset+400000]+'\n');parts.append(name)
  index['schema_version']=2;index['capsule_parts']=parts
 (target/'index.json').write_text(json.dumps(index,indent=2)+'\n')
 return {k:v for k,v in index.items() if k!='files'}

def restore(root,data,expected_sha,known=None):
 if sha(data)!=expected_sha:raise ValueError('Capsule SHA-256 mismatch')
 receipt_path=root/'.resume-local.json'
 receipt=json.loads(receipt_path.read_text()) if receipt_path.exists() else {'files':{}}
 previous=receipt.get('files',{});known=known or {}
 with zipfile.ZipFile(io.BytesIO(data)) as archive:
  entries=archive.infolist()
  if len(entries)>2000 or sum(x.file_size for x in entries)>MAX_BYTES:raise ValueError('Capsule bounds exceeded')
  names=[x.filename for x in entries]
  if len(names)!=len(set(names)):raise ValueError('Duplicate capsule paths')
  manifest=json.loads(archive.read('_CAPSULE_INDEX.json'))
  if set(names)!=set(manifest['files'])|{'_CAPSULE_INDEX.json'}:raise ValueError('Capsule inventory mismatch')
  validated={}
  for name,meta in manifest['files'].items():
   target=safe_path(root,name)
   if target.exists() and not target.is_file():raise ValueError('File path occupied by directory: '+name)
   content=archive.read(name)
   if len(content)!=meta['bytes'] or sha(content)!=meta['sha256']:raise ValueError('Capsule entry mismatch: '+name)
   validated[name]=content
  root.mkdir(parents=True,exist_ok=True)
  result={'written':[],'unchanged':[],'conflicts':[]}
  next_receipt=dict(previous)
  for name,content in validated.items():
   path=safe_path(root,name);current=path.read_bytes() if path.is_file() else None
   digest=sha(content)
   if current is not None and sha(current)==digest:
    result['unchanged'].append(name);next_receipt[name]=digest;continue
   if current is not None:
    allowed=(sha(current)==previous[name]) if name in previous else gitsha(current) in known.get(name,[])
    if not allowed:result['conflicts'].append(name);continue
   path.parent.mkdir(parents=True,exist_ok=True)
   with tempfile.NamedTemporaryFile(dir=path.parent,delete=False) as stream:
    stream.write(content);temp=stream.name
   os.replace(temp,path)
   next_receipt[name]=digest;result['written'].append(name)
  receipt_path.write_text(json.dumps({'content_id':manifest['content_id'],'files':next_receipt},sort_keys=True)+'\n')
 return result

def asset_plan(root,group):
 manifest=json.loads((root/'recovery/assets.json').read_text())
 groups={'code':set(),'runtime':{'runtime'},'test':{'runtime','reference'},'art':{'reference'},'distribution':{'distribution'},'all':{'runtime','reference','distribution'}}
 selected=groups[group];missing=[];ready=0
 for entry in manifest['files']:
  if entry['group'] not in selected:continue
  path=safe_path(root,entry['path'])
  if path.is_file() and path.stat().st_size==entry['bytes'] and sha(path.read_bytes())==entry['sha256']:ready+=1
  else:missing.append(entry)
 return {'group':group,'ready':ready,'missing':missing,'download_bytes':sum(x['bytes'] for x in missing)}

def status(root):
 state=json.loads((root/'recovery/session.json').read_text())
 index_path=root/'recovery/index.json';changed=[];missing=[]
 if index_path.exists():
  index=json.loads(index_path.read_text())
  for name,meta in index['files'].items():
   p=root/name
   if not p.is_file():missing.append(name)
   elif sha(p.read_bytes())!=meta['sha256']:changed.append(name)
 runtime=asset_plan(root,'runtime')
 kit=json.loads((root/'recovery/devkit.json').read_text())
 tools={name:all((root.parent/path).exists() for path in entry['present_paths']) for name,entry in kit['tools'].items()}
 return {'version':state['app_version'],'checkpoint_status':state['checkpoint_status'],'current_task':state['current_task'],'next_action':state['next_action'],'source_changed':changed,'source_missing':missing,'runtime_assets_missing':[x['path'] for x in runtime['missing']],'tools_present':tools,'read_next':state['read_next']}

def main():
 p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=ROOT);sub=p.add_subparsers(dest='command',required=True)
 sub.add_parser('status');sub.add_parser('snapshot');plan=sub.add_parser('plan');plan.add_argument('--group',choices=['code','runtime','test','art','distribution','all'],default='code')
 r=sub.add_parser('restore');r.add_argument('--capsule',required=True,type=Path);r.add_argument('--sha256',required=True)
 args=p.parse_args();root=args.root.resolve()
 if args.command=='snapshot':result=make_capsule(root)
 elif args.command=='status':result=status(root)
 elif args.command=='plan':result=asset_plan(root,args.group)
 else:
  known_path=root/'recovery/known_sources.json';known=json.loads(known_path.read_text()) if known_path.exists() else {}
  result=restore(root,base64.b64decode(args.capsule.read_text()),args.sha256,known)
 print(json.dumps(result,ensure_ascii=False,indent=2))
 if args.command=='restore' and result['conflicts']:return 2
 return 0
if __name__=='__main__':raise SystemExit(main())
