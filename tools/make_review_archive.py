#!/usr/bin/env python3
"""Export reviewed source and pinned active runtime art/font, never model weights."""
import argparse,hashlib,json,zipfile
from pathlib import Path
import resume
ROOT=Path(__file__).resolve().parents[1]
def create(root,output):
    entries=resume.source_entries(root)
    retired=json.loads((root/"recovery/retired_paths.json").read_text()).get("files",[])
    for item in retired:entries.pop(item["path"],None)
    assets=json.loads((root/'recovery/assets.json').read_text())['files']
    for item in assets:
        if item['group']!='runtime':continue
        path=resume.safe_path(root,item['path'])
        data=path.read_bytes()
        if len(data)!=item['bytes'] or resume.sha(data)!=item['sha256']:raise ValueError('Runtime asset mismatch: '+item['path'])
        entries[item['path']]=data
    required=['project.godot','CLAUDE_START_HERE.md','AGENTS.md','src/app.gd','native/desktop_bridge.ps1','assets/characters/leemon_01/master_v1.png','assets/fonts/NotoSansCJKsc-Regular.otf']
    if any(name not in entries for name in required):raise ValueError('Incomplete review project')
    forbidden={'.gguf','.safetensors','.onnx','.exe','.dll','.pck','.bin','.zip','.b64'}
    for name,data in entries.items():
        if Path(name).suffix.lower() in forbidden or name.startswith(('userdata/','captures/','downloads/','secrets/')) or len(data)>20*1024*1024:raise ValueError('Unexpected binary/private content: '+name)
    manifest={'version':json.loads((root/'config/product.json').read_text())['version'],'purpose':'Complete review source with active runtime art/font, without model weights or compiled engines','files':{name:{'bytes':len(data),'sha256':resume.sha(data)} for name,data in entries.items()},'excluded':['model weights','compiled engines/Windows preview','Godot import/cache','user data/credentials/captures','generated recovery capsule duplicates']}
    entries['REVIEW_ARCHIVE_MANIFEST.json']=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for name,data in sorted(entries.items()):
            info=zipfile.ZipInfo('Leemon_Project/'+name,(2026,10,29,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16;z.writestr(info,data)
    with zipfile.ZipFile(output) as z:
        if z.testzip():raise ValueError('Archive CRC failure')
        for name,meta in manifest['files'].items():
            data=z.read('Leemon_Project/'+name)
            if len(data)!=meta['bytes'] or resume.sha(data)!=meta['sha256']:raise ValueError('Archive byte mismatch: '+name)
    return {'archive':str(output),'bytes':output.stat().st_size,'sha256':resume.sha(output.read_bytes()),'files':len(entries),'model_weights_bundled':False}
def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();print(json.dumps(create(ROOT,a.output.resolve())))
if __name__=='__main__':main()
