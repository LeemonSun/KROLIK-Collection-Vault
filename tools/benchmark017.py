#!/usr/bin/env python3
"""Owned pinned-model exploratory A/B. No credentials/private traces enter receipts."""
import argparse,hashlib,json,os,secrets,socket,subprocess,tempfile,time,threading,urllib.request,resource,signal
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def proc_status(pid):
 direct=Path(f'/proc/{pid}/status')
 host=int(Path('/proc/self/stat').read_text().split()[0])
 children=Path(f'/proc/self/task/{host}/children').read_text().split()
 for child in children:
  path=Path('/proc')/child/'status'
  try:
   if any(line.startswith('NSpid:') and int(line.split()[-1])==pid for line in path.read_text().splitlines()):return path
  except OSError:pass
 raise FileNotFoundError('Owned worker host PID not resolved')
def main():
 signal.signal(signal.SIGINT,signal.default_int_handler)
 signal.signal(signal.SIGTERM,lambda *_args: (_ for _ in ()).throw(KeyboardInterrupt()))
 p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);p.add_argument('--cases',type=Path,required=True);p.add_argument('--threads',type=int,choices=[1,2,4],default=2);p.add_argument('--batch',type=int,choices=[32,128],default=32);p.add_argument('--variants',default='baseline,budget128');p.add_argument('--candidate-manifest',type=Path);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 model=a.fixture/'model.gguf';server_path=a.fixture/'runtime/llama-b11901/llama-server'
 candidate=json.loads(a.candidate_manifest.read_text()) if a.candidate_manifest else None
 if candidate:model=a.candidate_manifest.with_suffix('')/'model.gguf'
 manifest=json.loads((ROOT/'config/local_worker.json').read_text());expected=candidate['files'][0]['lfs']['sha256'] if candidate else manifest['model']['sha256'];assert hashlib.file_digest(model.open('rb'),'sha256').hexdigest()==expected
 cases=json.loads(a.cases.read_text());variants=a.variants.split(',');assert all(v in ['baseline','budget128','vendor'] for v in variants)
 token=secrets.token_hex(32)
 with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
 opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
 def call(path,body=None,timeout=180):
  data=None if body is None else json.dumps(body).encode()
  request=urllib.request.Request(f'http://127.0.0.1:{port}'+path,data=data,headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
  with opener.open(request,timeout=timeout) as r:return json.load(r)
 results={'schema':1,'model_sha256':expected,'candidate':candidate['id'] if candidate else None,'threads':a.threads,'batch':a.batch,'context':2048,'cases':[],'scope':'exploratory synthetic semantic cases; not Windows/product performance or statistical quality proof'}
 stop=threading.Event();peak=[0]
 with tempfile.TemporaryDirectory(prefix='leemon-bench017-') as td:
  env=dict(os.environ,LD_LIBRARY_PATH=str(server_path.parent));server=None;monitor=None
  try:
   with (Path(td)/'server.log').open('w') as log:
    start=time.monotonic();server=subprocess.Popen([str(server_path),'--model',str(model),'--host','127.0.0.1','--port',str(port),'--api-key',token,'--alias','companion','--ctx-size','2048','--threads',str(a.threads),'--threads-batch',str(a.threads),'--parallel','1','--n-gpu-layers','0','--batch-size',str(a.batch),'--ubatch-size',str(a.batch),'--poll','0','--prio','-1','--no-ui','--jinja','--reasoning','off'],env=env,stdout=log,stderr=log)
    def sample():
     while not stop.wait(.25):
      try:
       for line in proc_status(server.pid).read_text().splitlines():
        if line.startswith('VmRSS:'):peak[0]=max(peak[0],int(line.split()[1])*1024)
      except OSError:pass
    monitor=threading.Thread(target=sample,daemon=True);monitor.start()
    while time.monotonic()-start<90:
     if server.poll() is not None:raise RuntimeError('Owned server exited')
     try:call('/v1/models',timeout=1);break
     except Exception:time.sleep(.1)
    else:raise TimeoutError('Owned worker startup')
    results['startup_ms']=round((time.monotonic()-start)*1000)
    for variant in variants:
     for case in cases:
      row={'id':case['id'],'variant':variant};t=time.monotonic()
      body={'model':'companion','messages':case['messages'],'max_tokens':256 if variant=='budget128' else 128,'temperature':.4,'top_p':.9,'top_k':40,'min_p':0,'seed':42,'cache_prompt':True,'chat_template_kwargs':{'enable_thinking':variant=='budget128'},'reasoning_format':'deepseek'}
      if variant=='budget128':body['reasoning_budget_tokens']=128
      if variant=='vendor':body.update(temperature=1.0,top_p=1.0,top_k=20,presence_penalty=2.0,repeat_penalty=1.0)
      try:
       response=call('/v1/chat/completions',body)
       message=response['choices'][0]['message'];row.update(answer=message.get('content',''),reasoning_chars=len(message.get('reasoning_content') or ''),finish=response['choices'][0].get('finish_reason'),usage=response.get('usage'),timings=response.get('timings'))
      except Exception as e:row.update(error=type(e).__name__)
      row['wall_ms']=round((time.monotonic()-t)*1000);assert token not in json.dumps(row)
      results['cases'].append(row);results['worker_peak_rss_bytes']=peak[0] or None;a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n');print(json.dumps(row,ensure_ascii=False),flush=True)
  finally:
   stop.set()
   if monitor:monitor.join(timeout=2)
   if server is not None:
    server.terminate()
    try:server.wait(timeout=8)
    except subprocess.TimeoutExpired:server.kill();server.wait(timeout=5)
   # This process owns only the one worker child. Kernel rusage avoids PID-namespace
   # /proc ambiguity and includes the worker peak through termination.
   usage=resource.getrusage(resource.RUSAGE_CHILDREN)
   results['worker_peak_rss_bytes']=int(usage.ru_maxrss)*1024
   results['worker_cpu_seconds']=usage.ru_utime+usage.ru_stime
   results['rss_method']='Linux kernel RUSAGE_CHILDREN after owned worker exit; not Windows/app-total RSS'
   a.out.write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
 return 0
if __name__=='__main__':raise SystemExit(main())
