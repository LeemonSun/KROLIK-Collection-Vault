#!/usr/bin/env python3
"""Hash-guarded content update: reuse unchanged PCK blocks, keep model/profile intact."""
import argparse,base64,hashlib,json,shutil,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def sha(data):return hashlib.sha256(data).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--from-version',default='0.3.1');p.add_argument('--to-version',default='0.3.2');p.add_argument('--old-pack',required=True,type=Path);p.add_argument('--new-pack',required=True,type=Path);p.add_argument('--exe',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
 slot='fix'+a.to_version.replace('.','');out=a.output.resolve();data_dir=out/slot;data_dir.mkdir(parents=True,exist_ok=True)
 old=a.old_pack.read_bytes();new=a.new_pack.read_bytes();ops=[]
 for pos in range(0,len(new),65536):
  block=new[pos:pos+65536];offset=old.find(block)
  if offset>=0:
   if ops and ops[-1]['kind']=='copy' and ops[-1]['offset']+ops[-1]['length']==offset:ops[-1]['length']+=len(block)
   else:ops.append({'kind':'copy','offset':offset,'length':len(block)})
  else:ops.append({'kind':'literal','data':base64.b64encode(block).decode()})
 m={'schema_version':1,'from':a.from_version,'to':a.to_version,'exe_sha256':sha(a.exe.read_bytes()),'old_pack_sha256':sha(old),'pack_sha256':sha(new),'pack_bytes':len(new),'operations':ops}
 assert b''.join(old[x['offset']:x['offset']+x['length']] if x['kind']=='copy' else base64.b64decode(x['data']) for x in ops)==new
 (data_dir/'content_delta.json').write_text(json.dumps(m,separators=(',',':'))+'\n')
 shutil.copyfile(ROOT/'START_WINDOWS.cmd',data_dir/'START_WINDOWS.cmd')
 script=r'''$ErrorActionPreference='Stop';
$base=$env:COMPANION_PATCH_ROOT;
if([string]::IsNullOrWhiteSpace($base)){throw 'COMPANION_PATCH_ROOT is required.'};
$m=Get-Content -LiteralPath (Join-Path $base 'fix032/content_delta.json') -Raw | ConvertFrom-Json;
$target=$base;
if(-not (Test-Path -LiteralPath (Join-Path $target 'Companion.exe'))){$target=Join-Path $base 'build/windows-preview/Companion_Preview'};
$exe=Join-Path $target 'Companion.exe'; $pack=Join-Path $target 'Companion.pck';
if(-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $pack -PathType Leaf)){throw 'Put this patch beside the 0.3.1 EXE and PCK. For older builds use the complete 0.3.2 ZIP.'};
if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $m.exe_sha256){throw 'Unknown EXE preserved. Use the complete 0.3.2 ZIP.'};
$current=(Get-FileHash -LiteralPath $pack -Algorithm SHA256).Hash;
if($current -ne $m.old_pack_sha256 -and $current -ne $m.pack_sha256){throw 'This update requires the original 0.3.1 PCK. Unknown files preserved.'};
$running=Get-Process -Name Companion -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq $exe};
if($running){throw 'Close Companion in Task Manager, then apply this update.'};
$pending=$pack+'.032.pending'; $backup=$pack+'.before-0.3.2';
if($current -ne $m.pack_sha256){
 $inputStream=[IO.File]::OpenRead($pack); $outputStream=[IO.File]::Open($pending,[IO.FileMode]::Create);
 try { $buffer=New-Object byte[] 1048576;
  foreach($op in $m.operations){
   if($op.kind -eq 'copy'){
    $inputStream.Position=[long]$op.offset; $remaining=[long]$op.length;
    while($remaining -gt 0){$n=$inputStream.Read($buffer,0,[int][Math]::Min($buffer.Length,$remaining));if($n -le 0){throw 'Unexpected end of base pack.'};$outputStream.Write($buffer,0,$n);$remaining-=$n};
   } elseif($op.kind -eq 'literal'){$bytes=[Convert]::FromBase64String($op.data);$outputStream.Write($bytes,0,$bytes.Length)} else {throw 'Unknown update operation.'};
  };
 } finally {$outputStream.Dispose();$inputStream.Dispose()};
 if((Get-FileHash -LiteralPath $pending -Algorithm SHA256).Hash -ne $m.pack_sha256){Remove-Item -LiteralPath $pending -Force;throw 'Update hash mismatch. Original preserved.'};
 Copy-Item -LiteralPath $pack -Destination $backup -Force;
 try {Move-Item -LiteralPath $pending -Destination $pack -Force} catch {Copy-Item -LiteralPath $backup -Destination $pack -Force;throw};
};
$candidates=@($base);$parent=[IO.DirectoryInfo]$target;
for($i=0;$i -lt 3 -and $parent.Parent;$i++){$parent=$parent.Parent};$candidates+=@($parent.FullName);
foreach($candidate in ($candidates | Select-Object -Unique)){
 $launcher=Join-Path $candidate 'START_WINDOWS.cmd';$manifestPath=Join-Path $candidate 'downloads/preview-manifest.json';
 if(Test-Path -LiteralPath $manifestPath){
  $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json;
  $manifest | Add-Member -NotePropertyName pack_sha256 -NotePropertyValue $m.pack_sha256 -Force;
  $manifest.version=$m.to;$manifest.exe_sha256=$m.exe_sha256;
  $utf8=New-Object System.Text.UTF8Encoding -ArgumentList @($false);
  [IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 12),$utf8);
  if(Test-Path -LiteralPath $launcher){Copy-Item -LiteralPath $launcher -Destination ($launcher+'.before-0.3.2') -Force;Copy-Item -LiteralPath (Join-Path $base 'fix032/START_WINDOWS.cmd') -Destination $launcher -Force};
 };
};
Write-Output '0.3.2 ready. Start Companion.exe. Model and profile unchanged.';
'''
 script=script.replace('0.3.1','BASE_VERSION').replace('0.3.2',a.to_version).replace('BASE_VERSION',a.from_version).replace('fix032',slot).replace('.032.pending','.'+a.to_version.replace('.','')+'.pending')
 (data_dir/'Apply-Update.ps1').write_text(script)
 inline=' '.join(x.strip() for x in script.splitlines() if x.strip());assert '"' not in inline
 cmd='@echo off\nsetlocal\nset "COMPANION_PATCH_ROOT=%~dp0"\npowershell.exe -NoLogo -NoProfile -Command "'+inline+'"\nif errorlevel 1 (\n echo Update failed. Keep the error above.\n pause\n exit /b 1\n)\necho Start Companion.exe.\nendlocal\n';assert len(max(cmd.splitlines(),key=len))<8000
 (out/('APPLY_FIX_'+a.to_version+'.cmd')).write_bytes(cmd.replace('\n','\r\n').encode('ascii'))
 instructions='''ИСПРАВЛЕНИЕ ЗАПУСКА 0.3.1 → 0.3.2\n\n1. Заверши Companion через диспетчер задач, если он висит в фоне.\n2. Распакуй ZIP рядом с Companion.exe и Companion.pck.\n3. Запусти APPLY_FIX_0.3.2.cmd, затем Companion.exe.\n\nДля старой версии 0.3 без установленного фикса 0.3.1 используй полный ZIP 0.3.2.\nТеперь персонаж — главное окно. Его можно вернуть через панель задач.\nИконка Signal в области уведомлений Windows: ЛКМ — вернуть персонажа и чат, ПКМ — настройки.\nЕсли арт не загрузится, откроется резервная панель.\nМодель и профиль не заменяются. До обновления ресурсный пакет проверяется по SHA-256; старая копия сохраняется.\nНативный запуск Windows здесь не проверен; проверены экспортированный пакет на Linux/X11 и фактическое применение PowerShell-патча на Linux.\n'''
 instructions=instructions.replace('0.3.1','BASE_VERSION').replace('0.3.2',a.to_version).replace('BASE_VERSION',a.from_version)
 (out/'READ_ME.txt').write_text(instructions,encoding='utf-8')
 archive=out.parent/('Companion_Fix_'+a.to_version+'.zip')
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for f in sorted(out.rglob('*')):
   if f.is_file():z.write(f,f.relative_to(out).as_posix())
 print(json.dumps({'patch':str(archive),'bytes':archive.stat().st_size,'sha256':sha(archive.read_bytes()),'literal_bytes':sum(len(base64.b64decode(x['data'])) for x in ops if x['kind']=='literal')}))
if __name__=='__main__':main()
