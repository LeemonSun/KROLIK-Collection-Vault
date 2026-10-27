#!/usr/bin/env python3
"""Package reviewed optional AI files beside an already verified app. Never uploads weights to Git."""
import argparse,hashlib,json,shutil,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def digest(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path,required=True);parser.add_argument('--ai',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    files=[]
    for key,config in [('text','local_worker'),('voice','voice_worker'),('vision','vision_asset')]:
        spec=json.loads((ROOT/f'config/{config}.json').read_text())
        if key=='vision':items=[(spec['file'],spec['sha256'],spec['bytes'])]
        else:items=[(spec['model']['file'],spec['model']['sha256'],spec['model']['bytes']),*[(f'runtime/{name}',sha,None) for name,sha in spec['runtime']['files'].items()]]
        for relative,sha,size in items:
            path=args.ai/key/relative
            if not path.is_file() or (size is not None and path.stat().st_size!=size) or digest(path)!=sha:raise SystemExit('Pinned bundle input mismatch: '+str(path))
            files.append((path,f'Companion_Preview/AI/{key}/{relative}',sha))
    provenance={'private_preview':True,'windows_executed_here':False,'original_model_training':False,'components':[{key:json.loads((ROOT/f'config/{config}.json').read_text())} for key,config in [('text','local_worker'),('voice','voice_worker'),('vision','vision_asset')]],'files':[{'path':name,'bytes':path.stat().st_size,'sha256':sha} for path,name,sha in files]}
    with zipfile.ZipFile(args.app) as source,zipfile.ZipFile(args.output,'w',zipfile.ZIP_DEFLATED,compresslevel=2,allowZip64=True) as archive:
        for info in source.infolist():
            if info.filename.endswith('/BUILD_INFO.json'):
                build=json.loads(source.read(info));build['models_bundled']=True;archive.writestr(info.filename,json.dumps(build,indent=2)+'\n');continue
            with source.open(info) as src,archive.open(info.filename,'w',force_zip64=True) as dst:shutil.copyfileobj(src,dst,length=1048576)
        archive.writestr('Companion_Preview/AI_PROVENANCE.json',json.dumps(provenance,indent=2)+'\n')
        for path,name,_sha in files:archive.write(path,name)
    checksum=digest(args.output);args.output.with_suffix('.zip.sha256').write_text(checksum+'  '+args.output.name+'\n')
    print(json.dumps({'archive':str(args.output),'bytes':args.output.stat().st_size,'sha256':checksum,'files':len(files)}),flush=True)
if __name__=='__main__':main()
