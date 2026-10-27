#!/usr/bin/env python3
"""Build a one-time, hash-guarded 0.3 -> 0.3.1 file patch. Never touches profile/model data."""
import argparse,base64,hashlib,json,shutil,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--old-exe',required=True,type=Path);p.add_argument('--new-dir',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
 out=a.output.resolve();data_dir=out/'fix031';data_dir.mkdir(parents=True,exist_ok=True)
 old=a.old_exe.read_bytes();new=(a.new_dir/'Companion.exe').read_bytes();ops=[]
 for pos in range(0,len(new),65536):
  block=new[pos:pos+65536]
  if old[pos:pos+len(block)]==block:
   if ops and ops[-1]['kind']=='copy' and ops[-1]['offset']+ops[-1]['length']==pos:ops[-1]['length']+=len(block)
   else:ops.append({'kind':'copy','offset':pos,'length':len(block)})
  else:ops.append({'kind':'literal','data':base64.b64encode(block).decode()})
 pack=a.new_dir/'Companion.pck'
 manifest={'schema_version':1,'from':'0.3.0','to':'0.3.1','old_exe_sha256':hashlib.sha256(old).hexdigest(),'new_exe_sha256':hashlib.sha256(new).hexdigest(),'new_exe_bytes':len(new),'pack_sha256':sha(pack),'pack_bytes':pack.stat().st_size,'operations':ops}
 (data_dir/'engine_delta.json').write_text(json.dumps(manifest,separators=(',',':'))+'\n');shutil.copy2(pack,data_dir/'Companion.pck')
 script=r'''$ErrorActionPreference='Stop';
$base=$env:COMPANION_PATCH_ROOT;
if([string]::IsNullOrWhiteSpace($base)){throw 'COMPANION_PATCH_ROOT is required.'};
$m=Get-Content -LiteralPath (Join-Path $base 'fix031/engine_delta.json') -Raw | ConvertFrom-Json;
$target=$base;
if(-not (Test-Path -LiteralPath (Join-Path $target 'Companion.exe'))){$target=Join-Path $base 'build/windows-preview/Companion_Preview'};
$exe=Join-Path $target 'Companion.exe'; $pack=Join-Path $target 'Companion.pck';
$sourcePack=Join-Path $base 'fix031/Companion.pck';
if(Test-Path -LiteralPath $pack -PathType Container){throw 'Companion.pck is a folder. No files changed.'};
$backupExe=$exe+'.before-0.3.1'; $backupPack=$pack+'.before-0.3.1';
if(-not (Test-Path -LiteralPath $exe)){throw 'Put the patch beside Companion.exe, or in the GitHub project folder.'};
if((Get-FileHash -LiteralPath $sourcePack -Algorithm SHA256).Hash -ne $m.pack_sha256){throw 'Patch resource integrity check failed. No app files changed.'};
$current=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash;
if($current -eq $m.new_exe_sha256 -and (Test-Path -LiteralPath $pack) -and (Get-FileHash -LiteralPath $pack -Algorithm SHA256).Hash -eq $m.pack_sha256){Write-Output '0.3.1 already installed.'; exit 0};
if($current -ne $m.old_exe_sha256 -and $current -ne $m.new_exe_sha256){throw 'This patch requires the original 0.3 build. Unknown EXE left untouched.'};
$running=Get-Process -Name Companion -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq $exe};
if($running){throw 'Close Companion, then run this patch again.'};
$pendingExe=$exe+'.031.pending'; $pendingPack=$pack+'.031.pending';
$replaceExe=$current -ne $m.new_exe_sha256;
if($replaceExe){
 $inputStream=[IO.File]::OpenRead($exe); $outputStream=[IO.File]::Open($pendingExe,[IO.FileMode]::Create);
 try { $buffer=New-Object byte[] 1048576;
  foreach($op in $m.operations){
   if($op.kind -eq 'copy'){
    $inputStream.Position=[long]$op.offset; $remaining=[long]$op.length;
    while($remaining -gt 0){$n=$inputStream.Read($buffer,0,[int][Math]::Min($buffer.Length,$remaining)); if($n -le 0){throw 'Unexpected end of original EXE.'}; $outputStream.Write($buffer,0,$n); $remaining-=$n};
   } elseif($op.kind -eq 'literal'){$bytes=[Convert]::FromBase64String($op.data); $outputStream.Write($bytes,0,$bytes.Length)} else {throw 'Unknown patch operation.'};
  };
 } finally {$outputStream.Dispose(); $inputStream.Dispose()};
 if((Get-FileHash -LiteralPath $pendingExe -Algorithm SHA256).Hash -ne $m.new_exe_sha256){Remove-Item -LiteralPath $pendingExe -Force; throw 'Reconstructed EXE hash mismatch. Original preserved.'};
};
Copy-Item -LiteralPath $sourcePack -Destination $pendingPack -Force;
$hadPack=Test-Path -LiteralPath $pack;
$launcherPath=$null; $launcherBackup=$null;
$candidates=@($base);
$parent=[IO.DirectoryInfo]$target;
for($i=0;$i -lt 3 -and $parent.Parent;$i++){$parent=$parent.Parent};
$candidates+=@($parent.FullName);
foreach($candidate in ($candidates | Select-Object -Unique)){
 $candidateManifest=Join-Path $candidate 'downloads/preview-manifest.json';
 if(Test-Path -LiteralPath $candidateManifest){
  $launcher=Get-Content -LiteralPath $candidateManifest -Raw | ConvertFrom-Json;
  if($launcher.exe_sha256 -eq $m.old_exe_sha256){$launcherPath=$candidateManifest; $launcherBackup=$launcherPath+'.before-0.3.1'; break};
 };
};
if($replaceExe){Copy-Item -LiteralPath $exe -Destination $backupExe -Force};
if($hadPack){Copy-Item -LiteralPath $pack -Destination $backupPack -Force};
try {
 if($replaceExe){Move-Item -LiteralPath $pendingExe -Destination $exe -Force};
 Move-Item -LiteralPath $pendingPack -Destination $pack -Force;
 if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $m.new_exe_sha256 -or (Get-FileHash -LiteralPath $pack -Algorithm SHA256).Hash -ne $m.pack_sha256){throw 'Installed file check failed.'};
 if($launcherPath){
  Copy-Item -LiteralPath $launcherPath -Destination $launcherBackup -Force;
  $launcher.exe_sha256=$m.new_exe_sha256; $launcher.version='0.3.1-desktop-fix';
  $json=$launcher | ConvertTo-Json -Depth 12;
  $utf8=New-Object System.Text.UTF8Encoding -ArgumentList @($false);
  [IO.File]::WriteAllText($launcherPath,$json,$utf8);
 };
} catch {
 if($launcherBackup -and (Test-Path -LiteralPath $launcherBackup)){Copy-Item -LiteralPath $launcherBackup -Destination $launcherPath -Force};
 if($replaceExe -and (Test-Path -LiteralPath $backupExe)){Copy-Item -LiteralPath $backupExe -Destination $exe -Force};
 if($hadPack){Copy-Item -LiteralPath $backupPack -Destination $pack -Force} elseif(Test-Path -LiteralPath $pack){Remove-Item -LiteralPath $pack -Force};
 throw;
};
Write-Output 'Update 0.3.1 complete. Start Companion.exe. Model and profile were not changed.';
'''
 (data_dir/'Apply-Fix.ps1').write_text(script)
 inline=' '.join(x.strip() for x in script.splitlines() if x.strip())
 assert '"' not in inline
 cmd='@echo off\nsetlocal\nset "COMPANION_PATCH_ROOT=%~dp0"\necho Applying Companion 0.3 to 0.3.1 fix. Close the app first.\npowershell.exe -NoLogo -NoProfile -Command "'+inline+'"\nif errorlevel 1 (\n echo Update failed. Keep the error above for diagnostics.\n pause\n exit /b 1\n)\necho Start Companion.exe.\nendlocal\n'
 assert len(max(cmd.splitlines(),key=len))<8000
 (out/'APPLY_FIX_0.3.1.cmd').write_bytes(cmd.replace('\n','\r\n').encode('ascii'))
 (out/'READ_ME.txt').write_text('''ИСПРАВЛЕНИЕ 0.3 → 0.3.1\n\n1. Закрой Companion.\n2. Распакуй содержимое этого ZIP в папку с Companion.exe.\n   Если запускал через GitHub/START_WINDOWS.cmd, можно распаковать в корень того проекта.\n3. Запусти APPLY_FIX_0.3.1.cmd. Дождись сообщения об успешном обновлении.\n4. Открой Companion.exe. Клик по персонажу — разговор; ПКМ — меню.\n\nУже установленная модель и данные пользователя сохраняются.\nПатч проверяет исходный EXE и новые файлы по SHA-256.\nНеизвестную версию не заменяет; сохраняет предыдущий EXE как .before-0.3.1.\nПосле обновления рядом с EXE должен оставаться Companion.pck.\nСледующие обновления контента смогут заменять этот файл отдельно.\n\nЭто исправление интерфейса. Полноценный риг, жесты, распознавание речи,\nсамостоятельное исследование страниц и Steam Cloud ещё не готовы.\nКонтроль целостности не является цифровой подписью издателя.\n''',encoding='utf-8')
 archive=out.parent/'Companion_Fix_0.3.1.zip'
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for f in sorted(out.rglob('*')):
   if f.is_file() and not any(x.startswith('.') for x in f.relative_to(out).parts):z.write(f,f.relative_to(out).as_posix())
 archive.with_suffix('.zip.sha256').write_text(sha(archive)+'  '+archive.name+'\n')
 print(json.dumps({'patch':str(archive),'bytes':archive.stat().st_size,'sha256':sha(archive),'delta_operations':len(ops),'literal_bytes':sum(len(base64.b64decode(x['data'])) for x in ops if x['kind']=='literal')}))
if __name__=='__main__':main()
