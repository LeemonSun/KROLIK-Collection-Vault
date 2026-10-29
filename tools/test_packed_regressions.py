#!/usr/bin/env python3
"""External regressions against exported resources, without shipping test fixtures in the app."""
import argparse,hashlib,json,os,subprocess,tempfile,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CASES=['repair027','orbit026','agent025','observation024','draft016','discovery023','effects023','tasks022','logic_app021','evidence021','chat_draft020','control_context019','verification019','adaptive015','composer017','window_reader','exported_content']
def main():
 p=argparse.ArgumentParser();p.add_argument('--godot',type=Path,required=True);p.add_argument('--pack',type=Path,required=True);p.add_argument('--pwsh',type=Path,required=True);a=p.parse_args()
 version=json.loads((ROOT/'config/product.json').read_text())['version']
 env=dict(os.environ,COMPANION_PWSH=str(a.pwsh.resolve()),LEEMON_EXPECT_VERSION=version,COMPANION_HELPER_SHA=hashlib.sha256((ROOT/'native/desktop_bridge.ps1').read_bytes()).hexdigest(),COMPANION_ACCESS_HELPER_SHA=hashlib.sha256((ROOT/'native/accessibility_bridge.ps1').read_bytes()).hexdigest())
 failures=[]
 for name in CASES:
  with tempfile.TemporaryDirectory(prefix='leemon-packed-regression-') as td:
   script=ROOT/'tests'/('test_'+name+'.gd')
   if name=='draft016':
    # Its nested fake-class fixture is intentionally not in the distributed pack.
    copied=Path(td)/'draft016.gd';copied.write_text(script.read_text().replace('res://tests/test_adaptive015.gd',(ROOT/'tests/test_adaptive015.gd').as_posix()));script=copied
   result=subprocess.run([str(a.godot.resolve()),'--headless','--main-pack',str(a.pack.resolve()),'--script',str(script),'--','--test-mode'],cwd=a.pack.resolve().parent,env=dict(env,XDG_DATA_HOME=td,XDG_CONFIG_HOME=td),capture_output=True,text=True,timeout=90)
  log=result.stdout+result.stderr;(ROOT/'reports'/('pack_'+name+'.txt')).write_text(log)
  ok=result.returncode==0 and 'SCRIPT ERROR:' not in log and '\nERROR:' not in log
  print(name+(': PASS' if ok else ': FAIL'),flush=True)
  if not ok:failures.append(name);print(log,flush=True)
 return int(bool(failures))
if __name__=='__main__':raise SystemExit(main())
