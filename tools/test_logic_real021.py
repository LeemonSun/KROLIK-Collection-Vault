#!/usr/bin/env python3
"""Own one pinned worker for bounded categorical interpretation and deterministic solver pilot."""
import argparse,hashlib,json,os,pathlib,secrets,socket,subprocess,tempfile,time,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--kit',type=pathlib.Path,required=True);p.add_argument('--godot',type=pathlib.Path,required=True);a=p.parse_args()
 meta=json.loads((a.kit/'provenance.json').read_text());model=a.kit/'current2b.gguf';assert hashlib.file_digest(model.open('rb'),'sha256').hexdigest()==meta['current2b_sha256']
 server_path=next((a.kit/'runtime').rglob('llama-server'));token=secrets.token_hex(32)
 with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
 client=urllib.request.build_opener(urllib.request.ProxyHandler({}));server=None
 with tempfile.TemporaryDirectory(prefix='leemon-real021-') as profile:
  try:
   with (pathlib.Path(profile)/'worker.log').open('w') as log:
    server=subprocess.Popen([str(server_path),'--model',str(model),'--host','127.0.0.1','--port',str(port),'--api-key',token,'--alias','companion','--ctx-size','2048','--threads','2','--threads-batch','2','--parallel','1','--n-gpu-layers','0','--batch-size','32','--ubatch-size','32','--poll','0','--prio','-1','--no-ui','--jinja','--reasoning','off','--cache-ram','0','--ctx-checkpoints','0'],stdout=log,stderr=log,env=dict(os.environ,LD_LIBRARY_PATH=str(server_path.parent)))
    for _ in range(900):
     if server.poll() is not None:raise RuntimeError('Worker exited')
     try:
      req=urllib.request.Request(f'http://127.0.0.1:{port}/v1/models',headers={'Authorization':'Bearer '+token})
      with client.open(req,timeout=1):break
     except Exception:time.sleep(.1)
    else:raise TimeoutError('Worker startup')
    env=dict(os.environ,XDG_DATA_HOME=profile,XDG_CONFIG_HOME=profile,LEEMON_TEST_PORT=str(port),LEEMON_TEST_TOKEN=token,LEEMON_REAL_REPORT=str(ROOT/'reports/logic021-real.json'))
    r=subprocess.run([str(a.godot),'--headless','--path',str(ROOT),'--script','res://tests/test_logic_real021.gd','--','--test-mode'],env=env,cwd=ROOT,capture_output=True,text=True,timeout=750)
    output=r.stdout+r.stderr;assert token not in output
    (ROOT/'reports/logic021-real.txt').write_text(output);print(output,flush=True)
    assert r.returncode==0 and 'SCRIPT ERROR:' not in output and '\nERROR:' not in output
  finally:
   if server is not None:
    server.terminate()
    try:server.wait(timeout=8)
    except subprocess.TimeoutExpired:server.kill();server.wait(timeout=5)
if __name__=='__main__':main()
