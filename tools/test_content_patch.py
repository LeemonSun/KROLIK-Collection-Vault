#!/usr/bin/env python3
"""Apply actual updater commands locally against real EXE/PCK bytes; isolate all writes."""
import argparse,hashlib,json,os,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def inline(p):return next(x for x in p.read_text().splitlines() if x.startswith('powershell.exe ')).split('-Command "',1)[1][:-1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--pwsh',type=Path,required=True);p.add_argument('--patch',type=Path,required=True);p.add_argument('--base',type=Path,required=True);a=p.parse_args();patch=a.patch.resolve();base=a.base.resolve();manifest=json.loads((patch/'fix032/content_delta.json').read_text());checks=[]
 def run(root,command=None,expect=True):
  r=subprocess.run([str(a.pwsh.resolve()),'-NoLogo','-NoProfile','-Command',command or inline(patch/'APPLY_FIX_0.3.2.cmd')],env=dict(os.environ,COMPANION_PATCH_ROOT=str(root),COMPANION_ROOT=str(root)),capture_output=True,text=True,timeout=120)
  if expect and r.returncode:raise AssertionError(r.stdout+r.stderr)
  if not expect:assert r.returncode!=0
  return r
 def prepare(root):
  shutil.copytree(patch/'fix032',root/'fix032');os.link(base/'Companion.exe',root/'Companion.exe');shutil.copyfile(base/'Companion.pck',root/'Companion.pck')
 with tempfile.TemporaryDirectory(prefix='companion-content-') as temp:
  root=Path(temp)/'spaces & русский';root.mkdir();prepare(root);sentinel=root/'profile.json';sentinel.write_text('keep')
  run(root);assert digest(root/'Companion.pck')==manifest['pack_sha256'];assert digest(root/'Companion.pck.before-0.3.2')==manifest['old_pack_sha256'];assert sentinel.read_text()=='keep';checks.append('Actual minified PowerShell application; exact new PCK, backup, profile retained, Unicode/& path')
  run(root);assert digest(root/'Companion.pck')==manifest['pack_sha256'];checks.append('Repeat application idempotent')
 with tempfile.TemporaryDirectory(prefix='companion-content-unknown-') as temp:
  root=Path(temp);prepare(root);(root/'Companion.pck').write_bytes(b'unknown');run(root,expect=False);assert (root/'Companion.pck').read_bytes()==b'unknown';checks.append('Unknown base preserved')
 with tempfile.TemporaryDirectory(prefix='companion-content-bad-') as temp:
  root=Path(temp);prepare(root);p=root/'fix032/content_delta.json';m=json.loads(p.read_text());m['pack_sha256']='0'*64;p.write_text(json.dumps(m));run(root,expect=False);assert digest(root/'Companion.pck')==manifest['old_pack_sha256'];checks.append('Corrupt reconstruction refused before replacement')
 with tempfile.TemporaryDirectory(prefix='companion-content-source-') as temp:
  root=Path(temp);shutil.copytree(ROOT/'downloads',root/'downloads');shutil.copyfile(ROOT/'START_WINDOWS.cmd',root/'START_WINDOWS.cmd');command=inline(root/'START_WINDOWS.cmd')
  # Replace only the final process launch: PE execution is unavailable on Linux.
  command="function Start-Process { param($FilePath); Write-Output ('LAUNCH '+$FilePath) }; "+command
  run(root,command);target=root/'build/windows-preview/Companion_Preview';assert digest(target/'Companion.pck')==manifest['pack_sha256'];assert digest(target/'Companion.exe')==manifest['exe_sha256'];checks.append('Fresh root launcher restores 0.3, applies 0.3.1 and 0.3.2, verifies final files')
  original=(target/'Companion.pck').stat().st_mtime_ns;run(root,command);assert (target/'Companion.pck').stat().st_mtime_ns==original;checks.append('Second root launch skips restoration and cannot downgrade 0.3.2')
 text='CONTENT_PATCH_TESTS: '+str(len(checks))+' scenarios PASS\n'+'\n'.join(checks)+'\nPowerShell 7/Linux; Windows CMD execution and native Windows UI remain unverified.\n';(ROOT/'reports/content_patch.txt').write_text(text);print(text)
if __name__=='__main__':main()
