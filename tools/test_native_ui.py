#!/usr/bin/env python3
"""Local isolated X11 UI test. No network, no real desktop capture or user data."""
import argparse,os,socket,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--godot',required=True,type=Path);p.add_argument('--xvfb-root',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--pack',type=Path);p.add_argument('--script',type=Path,default=ROOT/'tests/test_desktop_visual.gd');a=p.parse_args()
 dev=a.xvfb_root.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
 env=dict(os.environ,LD_LIBRARY_PATH=str(dev/'usr/lib/x86_64-linux-gnu'))
 link=Path('/usr/bin/xkbcomp');owned=False;server=None
 try:
  if not link.exists():link.symlink_to(dev/'usr/bin/xkbcomp');owned=True
  with (out/'xvfb.log').open('w') as log:
   server=subprocess.Popen([str(dev/'usr/bin/Xvfb'),':98','-screen','0','1366x768x24','-listen','tcp','-nolisten','unix','-nolisten','local','-ac','-xkbdir',str(dev/'usr/share/X11/xkb')],env=env,stdout=log,stderr=log)
   for _ in range(50):
    if server.poll() is not None:raise RuntimeError((out/'xvfb.log').read_text())
    try:
     with socket.create_connection(('127.0.0.1',6098),timeout=.2):break
    except OSError:time.sleep(.1)
   else:raise RuntimeError('Xvfb did not listen')
   env.update(DISPLAY='127.0.0.1:98',LIBGL_ALWAYS_SOFTWARE='1',COMPANION_VISUAL_OUTPUT=str(out),XDG_DATA_HOME=str(out/'user'),XDG_CONFIG_HOME=str(out/'user'))
   command=[str(a.godot.resolve()),'--audio-driver','Dummy','--display-driver','x11','--rendering-method','gl_compatibility','--path',str(ROOT)]
   if a.pack:command+=['--main-pack',str(a.pack.resolve())]
   command+=['--script',str(a.script.resolve()),'--','--test-mode']
   result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=90)
   output=result.stdout+result.stderr;(out/'godot.log').write_text(output);print(output)
   return int(result.returncode!=0 or 'SCRIPT ERROR:' in output or '\nERROR:' in output or '0 failures' not in output)
 finally:
  if server is not None:server.terminate();server.wait(timeout=5)
  if owned:link.unlink()
if __name__=='__main__':raise SystemExit(main())
