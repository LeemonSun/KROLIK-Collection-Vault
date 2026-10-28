#!/usr/bin/env python3
"""Pinned, owned CPU semantic comparison; synthetic data only, no production changes."""
import argparse,hashlib,json,os,pathlib,resource,secrets,signal,socket,subprocess,tempfile,time,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 signal.signal(signal.SIGINT,signal.default_int_handler)
 signal.signal(signal.SIGTERM,lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
 p=argparse.ArgumentParser();p.add_argument('--kit',type=pathlib.Path,required=True);p.add_argument('--model',choices=['current2b','candidate17b'],required=True);p.add_argument('--variants',default='production');p.add_argument('--cache-mode',choices=['inherited','bounded'],default='inherited');p.add_argument('--cases',type=pathlib.Path,required=True);p.add_argument('--out',type=pathlib.Path,required=True);a=p.parse_args()
 provenance=json.loads((a.kit/'provenance.json').read_text());model=a.kit/(a.model+'.gguf')
 expected=provenance['current2b_sha256' if a.model=='current2b' else 'candidate_sha256']
 assert hashlib.file_digest(model.open('rb'),'sha256').hexdigest()==expected
 servers=list((a.kit/'runtime').rglob('llama-server'));assert len(servers)==1;server_path=servers[0]
 variants=a.variants.split(',');assert all(v in ['production','compact','authoring'] for v in variants)
 cases=json.loads(a.cases.read_text());token=secrets.token_hex(32)
 with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
 opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
 def call(path,body=None,timeout=90):
  data=None if body is None else json.dumps(body).encode()
  req=urllib.request.Request(f'http://127.0.0.1:{port}'+path,data=data,headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
  with opener.open(req,timeout=timeout) as response:return json.load(response)
 report={'schema':1,'model':a.model,'model_sha256':expected,'runtime_version':'b11901','runtime_archive_sha256':provenance['runtime_archive_sha256'],'threads':2,'batch':32,'context':2048,'seed':42,'cache_prompt':False,'variants':variants,'cache_mode':a.cache_mode,'worker_cache_ram_mib':0 if a.cache_mode=='bounded' else 8192,'ctx_checkpoints':0 if a.cache_mode=='bounded' else 32,'cases':[],'scope':'synthetic exploratory CPU comparison; one seed, not Windows/app-total/statistical IQ proof; no private reasoning text'}
 def save():
  a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 with tempfile.TemporaryDirectory(prefix='leemon-bench020-') as td:
  server=None
  try:
   with (pathlib.Path(td)/'server.log').open('w') as log:
    env=dict(os.environ,LD_LIBRARY_PATH=str(server_path.parent))
    started=time.monotonic();server=subprocess.Popen([str(server_path),'--model',str(model),'--host','127.0.0.1','--port',str(port),'--api-key',token,'--alias','companion','--ctx-size','2048','--threads','2','--threads-batch','2','--parallel','1','--n-gpu-layers','0','--batch-size','32','--ubatch-size','32','--poll','0','--prio','-1','--no-ui','--jinja','--reasoning','off']+(['--cache-ram','0','--ctx-checkpoints','0'] if a.cache_mode=='bounded' else []),stdout=log,stderr=log,env=env)
    for _ in range(900):
     if server.poll() is not None:raise RuntimeError('Owned worker exited: '+(pathlib.Path(td)/'server.log').read_text()[-1500:])
     try:call('/v1/models',timeout=1);break
     except Exception:time.sleep(.1)
    else:raise TimeoutError('Owned worker startup')
    report['startup_ms']=round((time.monotonic()-started)*1000)
    for variant in variants:
     for spec in cases:
      if variant=='compact' and (spec['execution']!='model' or spec['category']=='uia'):continue
      if variant=='authoring' and spec['category'] not in ['draft_missing','draft_given']:continue
      row={k:spec[k] for k in ['id','locale','category','input','execution','manual_rubric']};row['variant']=variant
      if spec['execution']=='deterministic':
       row.update(answer=spec['answer'],route=spec['route'],inference=False);report['cases'].append(row);save();continue
      options=spec['options'];messages=spec.get('compact_messages',spec['messages']) if variant=='compact' else (spec.get('authoring_messages',spec['messages']) if variant=='authoring' else spec['messages'])
      row['prompt_sha256']=hashlib.sha256(json.dumps(messages,ensure_ascii=False,sort_keys=True).encode()).hexdigest()
      started=time.monotonic()
      try:
       rendered=call('/apply-template',{'messages':messages,'add_generation_prompt':True,'chat_template_kwargs':{'enable_thinking':False}})
       prompt=rendered.get('prompt',rendered.get('content',''))
       tokens=call('/tokenize',{'content':prompt,'add_special':False})['tokens'];row['preflight_tokens']=len(tokens)
       maximum=int(options.get('max_tokens',96))
       if len(tokens)+maximum+64>2048:raise ValueError('Context budget would overflow')
       body={'model':'companion','messages':messages,'max_tokens':maximum,'stream':False,'temperature':.4,'top_p':.9,'top_k':40,'min_p':0,'seed':42,'cache_prompt':False,'chat_template_kwargs':{'enable_thinking':False}}
       if options.get('companion_dialogue') and variant!='authoring':body.update(temperature=.55,top_p=.85,top_k=20,presence_penalty=.25,repeat_penalty=1.0)
       if 'response_schema' in options:body.update(response_format={'type':'json_object'},json_schema=options['response_schema'])
       response=call('/v1/chat/completions',body);choice=response['choices'][0];message=choice['message']
       row.update(answer=message.get('content') or '',finish=choice.get('finish_reason'),usage=response.get('usage'),timings=response.get('timings'),reasoning_chars=len(message.get('reasoning_content') or ''))
       if spec['category']=='uia':
        try:
         parsed=json.loads(row['answer']);row['choice_match']=parsed.get('choice')==spec['expected_choice'];row['literal_match']=parsed.get('text','')==spec['expected_text'] and not parsed.get('append',False)
        except (ValueError,AttributeError):row.update(choice_match=False,literal_match=False)
      except Exception as error:row['error']=type(error).__name__+': '+str(error)[:150]
      row['wall_ms']=round((time.monotonic()-started)*1000);assert token not in json.dumps(row)
      report['cases'].append(row);save();print(json.dumps(row,ensure_ascii=False),flush=True)
  finally:
   if server is not None:
    server.terminate()
    try:server.wait(timeout=8)
    except subprocess.TimeoutExpired:server.kill();server.wait(timeout=5)
   usage=resource.getrusage(resource.RUSAGE_CHILDREN);report['owned_worker_peak_rss_bytes']=int(usage.ru_maxrss)*1024;report['owned_worker_cpu_seconds']=usage.ru_utime+usage.ru_stime;report['rss_method']='Linux RUSAGE_CHILDREN after sole owned worker exit; not Windows or app-total';save()
if __name__=='__main__':main()
