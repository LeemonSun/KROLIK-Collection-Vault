#!/usr/bin/env python3
"""Exercise real two-file updates and failure paths against exported Windows bytes."""
import argparse,hashlib,json,os,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--pwsh',type=Path,required=True);p.add_argument('--package',type=Path,required=True);p.add_argument('--base',type=Path,required=True);a=p.parse_args()
 manifest=json.loads((a.package/'delta.json').read_text());checks=[]
 def prepare(folder):
  for name in ['Companion.exe','Companion.pck']:os.link(a.base/name,folder/name)
  package=folder/'support050';shutil.copytree(a.package,package)
  return package
 def run(folder,package,success=True):
  result=subprocess.run([str(a.pwsh),'-NoLogo','-NoProfile','-File',str(package/'apply.ps1'),'-Root',str(folder)],capture_output=True,text=True,timeout=45)
  if success:assert result.returncode==0,result.stdout+result.stderr
  else:assert result.returncode!=0
 with tempfile.TemporaryDirectory(prefix='leemon-update-') as temporary:
  folder=Path(temporary)/'unicode & русский';folder.mkdir();package=prepare(folder)
  sentinel=folder/'profile.txt';sentinel.write_text('keep')
  run(folder,package)
  for item in manifest['files']:assert digest(folder/item['name'])==item['sha256']
  assert sentinel.read_text()=='keep';checks.append('EXE/icon and PCK reconstructed exactly; unrelated profile preserved')
  old_times=[(folder/item['name']).stat().st_mtime_ns for item in manifest['files']]
  run(folder,package)
  assert old_times==[(folder/item['name']).stat().st_mtime_ns for item in manifest['files']];checks.append('Repeat application idempotent')
  assert len(list((package/'backups').glob('*.bak')))==2;checks.append('Both verified old files preserved in one support folder')
  (folder/'Companion.pck').unlink();os.link(a.base/'Companion.pck',folder/'Companion.pck')
  engine_time=(folder/'Companion.exe').stat().st_mtime_ns
  run(folder,package)
  assert (folder/'Companion.exe').stat().st_mtime_ns==engine_time
  assert digest(folder/'Companion.pck')==manifest['files'][1]['sha256'];checks.append('Mixed old/new state completes without rewriting the current engine')
 with tempfile.TemporaryDirectory(prefix='leemon-unknown-') as temporary:
  folder=Path(temporary);package=prepare(folder)
  (folder/'Companion.exe').unlink();(folder/'Companion.exe').write_bytes(b'unknown')
  run(folder,package,False)
  assert (folder/'Companion.exe').read_bytes()==b'unknown' and digest(folder/'Companion.pck')==manifest['files'][1]['old_sha256'];checks.append('Unknown version rejected before any replacement')
 with tempfile.TemporaryDirectory(prefix='leemon-corrupt-') as temporary:
  folder=Path(temporary);package=prepare(folder)
  value=json.loads((package/'delta.json').read_text());value['files'][1]['sha256']='0'*64;(package/'delta.json').write_text(json.dumps(value))
  run(folder,package,False)
  for item in manifest['files']:assert digest(folder/item['name'])==item['old_sha256']
  assert not list(folder.glob('.update-*'));checks.append('Corrupt second file blocks both replacements; staging cleaned')
 with tempfile.TemporaryDirectory(prefix='leemon-rollback-') as temporary:
  folder=Path(temporary);package=prepare(folder)
  bad_repo=folder/'bad-repository';(bad_repo/'downloads').mkdir(parents=True);(bad_repo/'downloads/preview-manifest.json').write_text('{bad')
  result=subprocess.run([str(a.pwsh),'-NoLogo','-NoProfile','-File',str(package/'apply.ps1'),'-Root',str(folder),'-RepositoryRoot',str(bad_repo)],capture_output=True,text=True,timeout=45)
  assert result.returncode!=0
  for item in manifest['files']:assert digest(folder/item['name'])==item['old_sha256']
  checks.append('Failure after replacement restores both original files')
 with tempfile.TemporaryDirectory(prefix='leemon-source-ready-') as temporary:
  repository=Path(temporary);folder=repository/'build/windows-preview/Companion_Preview';folder.mkdir(parents=True);package=prepare(folder)
  (repository/'downloads').mkdir();metadata=repository/'downloads/preview-manifest.json'
  metadata.write_text(json.dumps({'version':'0.4.0','exe_sha256':manifest['files'][0]['old_sha256'],'pack_sha256':manifest['files'][1]['old_sha256'],'packages':[]}))
  result=subprocess.run([str(a.pwsh),'-NoLogo','-NoProfile','-File',str(package/'apply.ps1'),'-Root',str(folder),'-RepositoryRoot',str(repository)],capture_output=True,text=True,timeout=45)
  assert result.returncode==0,result.stdout+result.stderr
  updated=json.loads(metadata.read_text());assert updated['version']==manifest['to'] and updated['exe_sha256']==manifest['files'][0]['sha256'] and updated['pack_sha256']==manifest['files'][1]['sha256']
  assert (repository/'START_WINDOWS.cmd').read_bytes()==(package/'START_WINDOWS.cmd').read_bytes()
  command=next(line for line in (repository/'START_WINDOWS.cmd').read_text().splitlines() if line.startswith('powershell.exe ')).split('-Command "',1)[1][:-1]
  command="function Start-Process {param($FilePath);Write-Output ('LAUNCH_VERIFIED '+$FilePath)}; "+command
  times=[(folder/item['name']).stat().st_mtime_ns for item in manifest['files']]
  result=subprocess.run([str(a.pwsh),'-NoLogo','-NoProfile','-Command',command],env=dict(os.environ,COMPANION_ROOT=str(repository)),capture_output=True,text=True,timeout=45)
  assert result.returncode==0 and 'LAUNCH_VERIFIED' in result.stdout,result.stdout+result.stderr
  assert times==[(folder/item['name']).stat().st_mtime_ns for item in manifest['files']]
  checks.append('Source launcher/metadata updated; ready branch cannot downgrade new EXE/icon or PCK')
 text='PREVIEW_UPDATE_TESTS: '+str(len(checks))+' scenarios PASS\n'+'\n'.join(checks)+'\nPowerShell 7/Linux; native Windows process/file locking still requires acceptance.\n'
 (ROOT/'reports/preview_update.txt').write_text(text);print(text)
if __name__=='__main__':main()
