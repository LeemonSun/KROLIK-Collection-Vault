// Connector contract tests, entirely local. No GitHub writes or network.
const fs=require('node:fs');const os=require('node:os');const path=require('node:path');
const vm=require('node:vm');const assert=require('node:assert/strict');
const {execFile}=require('node:child_process');
const project=path.resolve(__dirname,'..');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'companion-resume-test-'));
const root=path.join(temp,'restored');let head='baseline',created,storedTree;
const structuredContent=v=>({structuredContent:v});
const run=cmd=>new Promise(resolve=>execFile('/bin/bash',['-c',cmd],{maxBuffer:2*1024*1024},(err,stdout,stderr)=>resolve({exit_code:err?.code||0,output:stdout+stderr})));
const tools={
 exec_command:({cmd})=>run(cmd),
 apply_patch:async patch=>{const lines=patch.split('\n');const dest=lines[1].replace('*** Add File: ','');fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,lines.slice(2,-1).map(x=>x.slice(1)).join('\n')+'\n');return {};},
 mcp__codex_apps__github_fetch:async({url})=>{
  let v;if(url.includes('/git/ref/'))v={object:{sha:head}};
  else if(url.includes('/git/commits/'))v={tree:{sha:'tree'}};
  else if(url.includes('/git/trees/'))v={tree:[],truncated:false};
  else throw Error('Unexpected URL '+url);
  return structuredContent({content:JSON.stringify(v)});
 },
 mcp__codex_apps__github_fetch_file:async({path:p})=>structuredContent({content:fs.readFileSync(path.join(project,p),'utf8')}),
 mcp__codex_apps__github_create_tree:async args=>{storedTree=args;return structuredContent({sha:'next-tree'});},
 mcp__codex_apps__github_create_commit:async args=>{created=args;return structuredContent({sha:'next-head'});},
 mcp__codex_apps__github_update_ref:async args=>{assert.equal(args.expected_sha,head);assert.equal(args.force,false);head=args.sha;return structuredContent({});}
};
const context={tools,Date,Math};context.globalThis=context;vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(project,'tools/resume_bridge.js'),'utf8'),context);
(async()=>{
 try{
  const cold=await context.companionResume({root,action:'bootstrap'});assert.equal(cold.warm,false);assert(cold.written>100);assert.equal(cold.conflicts.length,0);
  assert(!fs.existsSync(path.join(root,'assets/character/desktop_body.png')));
  const target=path.join(root,'AGENTS.md');fs.appendFileSync(target,'\nlocal preserved edit\n');
  const warm=await context.companionResume({root,action:'bootstrap'});assert.equal(warm.warm,true);assert.equal(warm.written,0);assert(warm.status.source_changed.includes('AGENTS.md'));
  const assets=await context.companionResume({root,action:'assets',group:'code'});assert.equal(assets.downloaded.length,0);
  const saved=await context.companionResume({root,action:'checkpoint'});assert.equal(saved.head,'next-head');assert(created.message.includes('[skip ci]'));assert(storedTree.tree_elements.some(x=>x.path==='recovery/source_capsule.b64'));
  assert(fs.readFileSync(target,'utf8').includes('local preserved edit'));
  head='someone-else';await assert.rejects(()=>context.companionResume({root,action:'checkpoint'}),/Remote changed/);
  console.log('Bridge: cold restore, warm resume, local edits, zero-asset code mode, checkpoint and remote lease passed.');
 } finally {fs.rmSync(temp,{recursive:true,force:true});}
})().catch(err=>{console.error(err);process.exitCode=1;});
