#!/usr/bin/env python3
"""Verified two-file preview delta: update engine/icon and PCK, never model/profile data."""
import argparse,base64,hashlib,json,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def sha(data):return hashlib.sha256(data).hexdigest()
def delta(old,new):
 size=65536
 index={sha(old[i:i+size]):i for i in range(0,len(old),size)}
 operations=[]
 for i in range(0,len(new),size):
  block=new[i:i+size];offset=index.get(sha(block),-1)
  if offset<0:offset=old.find(block)
  if offset>=0:
   if operations and operations[-1]['kind']=='copy' and operations[-1]['offset']+operations[-1]['length']==offset:operations[-1]['length']+=len(block)
   else:operations.append({'kind':'copy','offset':offset,'length':len(block)})
  else:operations.append({'kind':'literal','data':base64.b64encode(block).decode()})
 assert b''.join(old[op['offset']:op['offset']+op['length']] if op['kind']=='copy' else base64.b64decode(op['data']) for op in operations)==new
 return operations
SCRIPT=r'''param([Parameter(Mandatory=$true)][string]$Root,[string]$RepositoryRoot='')
$ErrorActionPreference='Stop'
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'delta.json') -Raw | ConvertFrom-Json
if($manifest.schema_version -ne 1 -or @($manifest.files).Count -ne 2){throw 'Invalid update package'}
if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){
 $exe=Join-Path $Root 'Companion.exe'
 $running=Get-Process -Name Companion -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq $exe}
 if($running){throw 'Close Companion before updating'}
}
$plans=@();$seen=@{}
foreach($file in $manifest.files){
 if($file.name -notin @('Companion.exe','Companion.pck') -or $seen.ContainsKey($file.name)){throw 'Unexpected update file'}
 $seen[$file.name]=$true
 $path=Join-Path $Root $file.name
 if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw 'Use the full preview ZIP for a missing program'}
 $current=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
 if($current -ne $file.old_sha256 -and $current -ne $file.sha256){throw 'Unknown version preserved; use full ZIP'}
 if($current -ne $file.sha256){$plans+=@{file=$file;path=$path}}
}
$stage=Join-Path $Root ('.update-'+[guid]::NewGuid().ToString('N'))
$changed=@()
try{
 if($plans.Count){$null=New-Item -ItemType Directory -Path $stage}
 foreach($plan in $plans){
  $file=$plan.file;$outputPath=Join-Path $stage $file.name
  $inputStream=[IO.File]::OpenRead($plan.path);$outputStream=[IO.File]::Create($outputPath)
  try{
   $buffer=New-Object byte[] 1048576
   foreach($op in $file.operations){
    if($op.kind -eq 'copy'){
     if($op.offset -lt 0 -or $op.length -lt 1 -or ($op.offset+$op.length) -gt $inputStream.Length){throw 'Invalid copy range'}
     $inputStream.Position=[long]$op.offset;$left=[long]$op.length
     while($left -gt 0){$count=$inputStream.Read($buffer,0,[int][Math]::Min($left,$buffer.Length));if($count -lt 1){throw 'Unexpected end of base file'};$outputStream.Write($buffer,0,$count);$left-=$count}
    }elseif($op.kind -eq 'literal'){$bytes=[Convert]::FromBase64String($op.data);$outputStream.Write($bytes,0,$bytes.Length)}else{throw 'Invalid operation'}
   }
  }finally{$inputStream.Dispose();$outputStream.Dispose()}
  if((Get-Item -LiteralPath $outputPath).Length -ne $file.bytes -or (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash -ne $file.sha256){throw 'Reconstruction failed integrity check'}
  $plan.staged=$outputPath
 }
 $backupRoot=Join-Path $PSScriptRoot 'backups'
 foreach($plan in $plans){
  $null=[IO.Directory]::CreateDirectory($backupRoot)
  $backup=Join-Path $backupRoot ($plan.file.name+'.'+$plan.file.old_sha256+'.bak')
  if(Test-Path -LiteralPath $backup){if((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $plan.file.old_sha256){throw 'Unknown backup preserved'}}else{Copy-Item -LiteralPath $plan.path -Destination $backup}
  if((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $plan.file.old_sha256){throw 'Backup failed integrity check'}
  $plan.backup=$backup
  [IO.File]::Replace($plan.staged,$plan.path,(Join-Path $stage ($plan.file.name+'.replaced')))
  $changed+=,$plan
 }
 foreach($file in $manifest.files){if((Get-FileHash -LiteralPath (Join-Path $Root $file.name) -Algorithm SHA256).Hash -ne $file.sha256){throw 'Final update verification failed'}}
 if($RepositoryRoot){
  $path=Join-Path $RepositoryRoot 'downloads/preview-manifest.json'
  if(Test-Path -LiteralPath $path){
   $metadata=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
   $metadata.version=$manifest.to
   $metadata.exe_sha256=($manifest.files | Where-Object {$_.name -eq 'Companion.exe'}).sha256
   $metadata.pack_sha256=($manifest.files | Where-Object {$_.name -eq 'Companion.pck'}).sha256
   [IO.File]::WriteAllText($path,($metadata | ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
   Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'START_WINDOWS.cmd') -Destination (Join-Path $RepositoryRoot 'START_WINDOWS.cmd') -Force
  }
 }
 Write-Output ('UPDATE_OK '+$manifest.to)
}catch{
 foreach($plan in $changed){Copy-Item -LiteralPath $plan.backup -Destination $plan.path -Force}
 throw
}finally{
 if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}
}
'''
def main():
 p=argparse.ArgumentParser();p.add_argument('--old',type=Path,required=True);p.add_argument('--new',type=Path,required=True);p.add_argument('--from-version',required=True);p.add_argument('--to-version',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 a.output.mkdir(parents=True,exist_ok=True)
 manifest={'schema_version':1,'from':a.from_version,'to':a.to_version,'files':[]}
 for name in ['Companion.exe','Companion.pck']:
  old=(a.old/name).read_bytes();new=(a.new/name).read_bytes()
  manifest['files'].append({'name':name,'old_sha256':sha(old),'sha256':sha(new),'bytes':len(new),'operations':delta(old,new)})
 (a.output/'delta.json').write_text(json.dumps(manifest,separators=(',',':'))+'\n')
 (a.output/'apply.ps1').write_text(SCRIPT)
 (a.output/'START_WINDOWS.cmd').write_bytes((ROOT/'START_WINDOWS.cmd').read_bytes())
 archive=a.output.parent/f'Companion_Update_{a.to_version}.zip'
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for file in sorted(a.output.iterdir()):
   if file.is_file():z.write(file,file.name)
 print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'sha256':sha(archive.read_bytes())}))
if __name__=='__main__':main()
