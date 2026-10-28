#!/usr/bin/env python3
"""Pinned matched-budget model comparison. Owns one CPU worker; no OS effects."""
import argparse,hashlib,json,os,pathlib,resource,secrets,socket,subprocess,tempfile,time,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--kit',type=pathlib.Path,required=True);p.add_argument('--candidate-kit',type=pathlib.Path,required=True);p.add_argument('--model',choices=['2b','4b'],required=True);p.add_argument('--mode',choices=['direct','think128','think256','think512'],default='direct');p.add_argument('--categories',default='');p.add_argument('--out',type=pathlib.Path,required=True);a=p.parse_args()
 provenance=json.loads((a.kit/'provenance.json').read_text());candidate=json.loads((a.candidate_kit/'provenance.json').read_text())
 model=a.kit/'current2b.gguf' if a.model=='2b' else a.candidate_kit/'qwen35_4b.gguf'
 expected=provenance['current2b_sha256'] if a.model=='2b' else candidate['sha256']
 assert hashlib.file_digest(model.open('rb'),'sha256').hexdigest()==expected
 server_path=next((a.kit/'runtime').rglob('llama-server'));token=secrets.token_hex(32)
 with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
 opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
 def call(path,body=None,timeout=100):
  req=urllib.request.Request(f'http://127.0.0.1:{port}'+path,data=None if body is None else json.dumps(body).encode(),headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
  with opener.open(req,timeout=timeout) as r:return json.load(r)
 report={'model':a.model,'sha256':expected,'runtime':'b11901','runtime_archive_sha256':provenance['runtime_archive_sha256'],'threads':2,'batch':32,'context':2048,'cache_ram':0,'ctx_checkpoints':0,'mode':a.mode,'seed':42,'cases':[],'scope':'synthetic real CPU inference, matched256answerbudget; notWindows/notstatisticalIQ/notrealOSexecution; no private reasoning text'}
 def save():a.out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 with tempfile.TemporaryDirectory(prefix='leemon-brain021-') as td:
  server=None
  try:
   with (pathlib.Path(td)/'worker.log').open('w') as log:
    start=time.monotonic();server=subprocess.Popen([str(server_path),'--model',str(model),'--host','127.0.0.1','--port',str(port),'--api-key',token,'--alias','companion','--ctx-size','2048','--threads','2','--threads-batch','2','--parallel','1','--n-gpu-layers','0','--batch-size','32','--ubatch-size','32','--poll','0','--prio','-1','--no-ui','--jinja','--reasoning','off','--cache-ram','0','--ctx-checkpoints','0'],stdout=log,stderr=log,env=dict(os.environ,LD_LIBRARY_PATH=str(server_path.parent)))
    for _ in range(900):
     if server.poll() is not None:raise RuntimeError('Owned worker exited')
     try:call('/v1/models',timeout=1);break
     except Exception:time.sleep(.1)
    else:raise TimeoutError('startup')
    report['startup_ms']=round((time.monotonic()-start)*1000)
    cases=json.loads((ROOT/'research/brain021-cases.json').read_text())
    if a.categories:cases=[x for x in cases if x['category'] in a.categories.split(',')]
    if a.mode in ['think128','think256','think512']:cases=[x for x in cases if x['category'] in ['liar','negative','arithmetic','plan']]
    for spec in cases:
     row={k:spec[k] for k in ['id','locale','category','input','rubric']};start=time.monotonic()
     reasoning_budget={'direct':0,'think128':128,'think256':256,'think512':512}[a.mode];thinking=reasoning_budget>0;limit=256+reasoning_budget
     try:
      rendered=call('/apply-template',{'messages':spec['messages'],'add_generation_prompt':True,'chat_template_kwargs':{'enable_thinking':thinking}})
      tokens=call('/tokenize',{'content':rendered.get('prompt',rendered.get('content','')),'add_special':False})['tokens'];row['prompt_tokens']=len(tokens)
      assert len(tokens)+limit+64<=2048
      body={'model':'companion','messages':spec['messages'],'max_tokens':limit,'temperature':.4,'top_p':.9,'top_k':40,'min_p':0,'seed':42,'cache_prompt':False,'chat_template_kwargs':{'enable_thinking':thinking}}
      if thinking:body.update(reasoning_budget_tokens=reasoning_budget,reasoning_format='deepseek')
      if 'schema' in spec:
       def canonical(value):
        if isinstance(value,dict):return {k:canonical(v) for k,v in value.items()}
        if isinstance(value,list):return [canonical(v) for v in value]
        return int(value) if isinstance(value,float) and value.is_integer() else value
       body.update(response_format={'type':'json_object'},json_schema=canonical(spec['schema']))
      response=call('/v1/chat/completions',body);choice=response['choices'][0];message=choice['message']
      row.update(answer=message.get('content') or '',finish=choice.get('finish_reason'),usage=response.get('usage'),timings=response.get('timings'),reasoning_chars=len(message.get('reasoning_content') or ''))
      if spec['category']=='uia':
       try:
        parsed=json.loads(row['answer']);row['choice_match']=parsed.get('choice')==spec['expected_choice'];row['literal_match']=parsed.get('text','')==spec['expected_text'] and not parsed.get('append',False)
       except (ValueError,AttributeError):row.update(choice_match=False,literal_match=False)
     except Exception as error:
      row['error']=type(error).__name__+': '+str(error)[:100]
      if isinstance(error,urllib.error.HTTPError):row['error_body']=error.read(1500).decode('utf-8',errors='replace').replace(token,'REDACTED')
     row['wall_ms']=round((time.monotonic()-start)*1000);assert token not in json.dumps(row);report['cases'].append(row);save();print(spec['id'],row.get('finish'),row['wall_ms'],flush=True)
  finally:
   if server is not None:
    server.terminate()
    try:server.wait(timeout=8)
    except subprocess.TimeoutExpired:server.kill();server.wait(timeout=5)
   usage=resource.getrusage(resource.RUSAGE_CHILDREN);report['owned_worker_peak_rss_bytes']=int(usage.ru_maxrss)*1024;report['owned_worker_cpu_seconds']=usage.ru_utime+usage.ru_stime;save()
if __name__=='__main__':main()
