#!/usr/bin/env python3
"""Own one authenticated Linux inference fixture; no model/runtime artifacts enter the repo."""
import argparse,hashlib,json,os,secrets,socket,subprocess,tempfile,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--fixture',type=Path,required=True);parser.add_argument('--godot',type=Path,required=True);a=parser.parse_args()
 model=a.fixture/'Qwen3-1.7B-Q8_0.gguf';server_path=a.fixture/'runtime/llama-b11901/llama-server'
 expected=json.loads((ROOT/'config/local_worker.json').read_text())['model']['sha256']
 assert hashlib.file_digest(model.open('rb'),'sha256').hexdigest()==expected
 with socket.socket() as reserve:reserve.bind(('127.0.0.1',0));port=reserve.getsockname()[1]
 token=secrets.token_hex(32)
 with tempfile.TemporaryDirectory(prefix='leemon-real-') as temporary:
  temporary=Path(temporary)
  env=dict(os.environ,XDG_DATA_HOME=str(temporary),XDG_CONFIG_HOME=str(temporary),COMPANION_TEST_PORT=str(port),COMPANION_TEST_TOKEN=token,LD_LIBRARY_PATH=str(server_path.parent))
  command=[str(server_path),'--model',str(model),'--host','127.0.0.1','--port',str(port),'--api-key',token,'--alias','companion','--ctx-size','2048','--threads','2','--threads-batch','2','--parallel','1','--n-gpu-layers','0','--batch-size','128','--ubatch-size','128','--poll','0','--prio','-1','--no-ui','--jinja','--reasoning','off']
  server=None
  try:
   with (temporary/'private-server.log').open('w') as log:
    server=subprocess.Popen(command,env=env,stdout=log,stderr=log)
    request=urllib.request.Request(f'http://127.0.0.1:{port}/v1/models',headers={'Authorization':'Bearer '+token})
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    deadline=time.monotonic()+90
    while time.monotonic()<deadline:
     if server.poll() is not None:raise RuntimeError('Owned fixture server failed to start; private log retained only during this run')
     try:
      with opener.open(request,timeout=1) as response:
       if response.status==200:break
     except Exception:time.sleep(.1)
    else:raise RuntimeError('Fixture startup timed out')
    result=subprocess.run([str(a.godot),'--headless','--path',str(ROOT),'--script','res://tests/test_real_leemon.gd','--','--test-mode'],env=env,capture_output=True,text=True,timeout=300)
    output=result.stdout+result.stderr
    assert token not in output
    (ROOT/'reports/real_leemon.txt').write_text(output)
    print(output)
    return int(result.returncode!=0 or 'SCRIPT ERROR:' in output or '\nERROR:' in output or '0 failures' not in output)
  finally:
   if server is not None:
    server.terminate()
    try:server.wait(timeout=10)
    except subprocess.TimeoutExpired:server.kill();server.wait(timeout=5)
if __name__=='__main__':raise SystemExit(main())
