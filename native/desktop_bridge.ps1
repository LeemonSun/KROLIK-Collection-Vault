param([Parameter(Mandatory=$true)][string]$RequestPath,[Parameter(Mandatory=$true)][string]$ResultPath)
$ErrorActionPreference='Stop'
$reply=@{status='failed';nonce=''}
function Normalize-Name([string]$value) {
 return ($value.ToLowerInvariant() -replace '[^\p{L}\p{N}]','')
}
function Get-AppCatalog {
 $items=[Collections.Generic.List[object]]::new()
 foreach($app in @(@{name='notepad';aliases=@('блокнот','记事本');path="$env:WINDIR\System32\notepad.exe"},@{name='calculator';aliases=@('калькулятор','calc','计算器');path="$env:WINDIR\System32\calc.exe"},@{name='paint';aliases=@('пейнт','画图');path="$env:WINDIR\System32\mspaint.exe"})) {
  if(Test-Path -LiteralPath $app.path -PathType Leaf){$items.Add($app)}
 }
 $shell=New-Object -ComObject WScript.Shell
 foreach($folder in @([Environment]::GetFolderPath('StartMenu'),[Environment]::GetFolderPath('CommonStartMenu'))) {
  if(-not $folder -or -not (Test-Path -LiteralPath $folder)){continue}
  foreach($link in Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1500) {
   if($link.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
   $shortcut=$shell.CreateShortcut($link.FullName);$path=[Environment]::ExpandEnvironmentVariables($shortcut.TargetPath)
   if(-not $path -or $path.StartsWith('\\') -or [IO.Path]::GetExtension($path) -ine '.exe' -or -not (Test-Path -LiteralPath $path -PathType Leaf)){continue}
   if($link.BaseName -match '(?i)uninstall|uninstaller|удалени|卸载'){continue}
   if([IO.Path]::GetFileNameWithoutExtension($path) -match '^(?i:cmd|powershell|pwsh|wscript|cscript|mshta|rundll32|regsvr32|installutil|python|pythonw|bash|wsl)$'){continue}
   # Shortcut arguments are not executable authority: launch only its resolved executable.
   $items.Add(@{name=$link.BaseName;aliases=@();path=$path})
  }
 }
 return $items.ToArray()
}
function Resolve-Target([string]$target,$catalog) {
 $key=Normalize-Name $target
 $aliases=@{ 'стим'='steam';'хром'='googlechrome';'опера'='opera';'операgx'='operagx';'проводник'='explorer';'проводникwindows'='explorer';'fileexplorer'='explorer';'文件资源管理器'='explorer' }
 if($aliases.ContainsKey($key)){$key=$aliases[$key]}
 if($key -eq 'explorer'){return @{kind='folder';path=[Environment]::GetFolderPath('UserProfile');name='Explorer'}}
 $folders=@{
  'downloads'='Downloads';'загрузки'='Downloads';'папкузагрузки'='Downloads';'下载'='Downloads';
  'documents'='MyDocuments';'документы'='MyDocuments';'папкудокументы'='MyDocuments';'文档'='MyDocuments';
  'desktop'='Desktop';'рабочийстол'='Desktop';'桌面'='Desktop';
  'pictures'='MyPictures';'изображения'='MyPictures';'图片'='MyPictures'
 }
 if($folders.ContainsKey($key)) {
  $path=if($folders[$key] -eq 'Downloads'){
   $known=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
   if($known -and $known.'{374DE290-123F-4565-9164-39C4925E467B}') {[Environment]::ExpandEnvironmentVariables($known.'{374DE290-123F-4565-9164-39C4925E467B}')}else{Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'}
  }else{[Environment]::GetFolderPath($folders[$key])}
  return @{kind='folder';path=$path;name=$target}
 }
 if($target -match '^[A-Za-z]:[\\/]' -and (Test-Path -LiteralPath $target -PathType Container)){return @{kind='folder';path=[IO.Path]::GetFullPath($target);name=$target}}
 $exact=@($catalog | Where-Object { (Normalize-Name $_.name) -eq $key -or @($_.aliases | Where-Object {(Normalize-Name $_) -eq $key}).Count -gt 0 })
 $matches=if($exact.Count){$exact}else{@($catalog | Where-Object {(Normalize-Name $_.name).Contains($key)})}
 $matches=@($matches | Group-Object {$_.path.ToLowerInvariant()} | ForEach-Object {$_.Group[0]})
 if($matches.Count -eq 1){return @{kind='app';path=$matches[0].path;name=$matches[0].name}}
 if($matches.Count -gt 1){return @{kind='ambiguous';choices=@($matches | Select-Object -First 8 | ForEach-Object {$_.name})}}
 return @{kind='missing'}
}
function Open-Target($resolved) {
 if($resolved.kind -eq 'folder') {
  if(-not $resolved.path -or -not (Test-Path -LiteralPath $resolved.path -PathType Container)){return @{status='missing'}}
  $shell=New-Object -ComObject Shell.Application
  $shell.Explore($resolved.path)
  for($attempt=0;$attempt -lt 24;$attempt++) {
   foreach($window in $shell.Windows()) {
    try{if($window.HWND -ne 0 -and [IO.Path]::GetFullPath($window.Document.Folder.Self.Path).TrimEnd('\') -ieq $resolved.path.TrimEnd('\')){return @{status='visible';name=$resolved.name}}}catch{}
   }
   Start-Sleep -Milliseconds 125
  }
  return @{status='started';name=$resolved.name}
 }
 if($resolved.kind -eq 'app') {
  $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$resolved.path;$start.UseShellExecute=$true
  $null=[Diagnostics.Process]::Start($start)
  for($attempt=0;$attempt -lt 24;$attempt++) {
   foreach($process in Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($resolved.path)) -ErrorAction SilentlyContinue) {
    try{if($process.Path -ieq $resolved.path -and $process.MainWindowHandle -ne 0){return @{status='visible';name=$resolved.name;identity=@{handle=[string]$process.MainWindowHandle.ToInt64();target_pid=$process.Id;started=[string]$process.StartTime.ToUniversalTime().Ticks;title=$process.MainWindowTitle;app=$process.ProcessName}}}}catch{}
   }
   Start-Sleep -Milliseconds 125
  }
  return @{status='started';name=$resolved.name}
 }
 return @{status=$resolved.kind;choices=$resolved.choices}
}
function Set-CompanionOverlay($request) {
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'Windows required'}
 if($request.handle -notmatch '^\d{1,19}$' -or $request.owner_pid -lt 1){throw 'Invalid window'}
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LeemonWindow {
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint processId);
 [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr GetWindowLongPtrW(IntPtr hwnd,int index);
 [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr SetWindowLongPtrW(IntPtr hwnd,int index,IntPtr value);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int w,int h,uint flags);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd,int command);
 public static long OverlayStyle(long original) { return (original|0x80L)&~0x40000L; }
 public static bool Overlay(IntPtr hwnd,uint expected) {
  uint actual; GetWindowThreadProcessId(hwnd,out actual);
  if(actual!=expected) return false;
  long original=GetWindowLongPtrW(hwnd,-20).ToInt64();
  long desired=OverlayStyle(original);
  if(desired==original) return true;
  ShowWindow(hwnd,0);
  SetWindowLongPtrW(hwnd,-20,new IntPtr(desired));
  SetWindowPos(hwnd,IntPtr.Zero,0,0,0,0,0x37);
  ShowWindow(hwnd,8);
  return GetWindowLongPtrW(hwnd,-20).ToInt64()==desired;
 }
}
'@
 if(-not [LeemonWindow]::Overlay([IntPtr]::new([long]$request.handle),[uint32]$request.owner_pid)){throw 'Window style failed'}
 return @{status='ok'}
}
function Open-Document($request) {
 $path=[IO.Path]::GetFullPath([string]$request.path)
 $folder=[IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Leemon'))
 if([IO.Path]::GetDirectoryName($path) -ine $folder -or [IO.Path]::GetFileName($path) -notmatch '^Leemon-[0-9T-]+-[a-f0-9]{16}\.(?:txt|docx)$' -or $request.sha256 -notmatch '^[a-f0-9]{64}$'){throw 'Not an owned draft'}
 $file=Get-Item -LiteralPath $path
 $parent=Get-Item -LiteralPath $folder
 if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 32768 -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $request.sha256){throw 'Draft changed'}
 $outcome=@{status='document_saved';name=$file.Name;path=$path}
 if($file.Extension -ieq '.docx'){
  $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$path;$start.UseShellExecute=$true
  try{$null=[Diagnostics.Process]::Start($start);$outcome.status='document_started'}catch{}
  return $outcome
 }
 $notepad=Join-Path $env:WINDIR 'System32/notepad.exe'
 if(-not (Test-Path -LiteralPath $notepad)){return $outcome}
 $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$notepad;$start.UseShellExecute=$true
 # A fixed, validated path is the only argument; file contents never become code.
 $start.Arguments='"'+$path+'"'
 try{$null=[Diagnostics.Process]::Start($start);$outcome.status='document_started'}catch{return $outcome}
 for($attempt=0;$attempt -lt 16;$attempt++) {
  foreach($process in Get-Process -Name notepad -ErrorAction SilentlyContinue) {
   if($process.MainWindowHandle -ne 0 -and $process.MainWindowTitle.Contains($file.Name)){$outcome.status='document_opened';return $outcome}
  }
  Start-Sleep -Milliseconds 100
 }
 return $outcome
}
try {
 if((Get-Item -LiteralPath $RequestPath).Length -gt 16384){throw 'Request too large'}
 $request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
 if($request.nonce -notmatch '^[a-f0-9]{32}$'){throw 'Invalid request'}
 $reply.nonce=$request.nonce
 if($request.operation -eq 'metrics') {
  if(@($request.pids).Count -gt 2){throw 'Too many processes'}
  $reply.operation='metrics';$reply.status='ok';$reply.items=@()
  foreach($processId in $request.pids) {
   if($processId -isnot [long] -and $processId -isnot [int]){throw 'Invalid process'}
   $process=Get-Process -Id $processId -ErrorAction SilentlyContinue
   if($process){$reply.items+=@{pid=[int]$processId;bytes=[long]$process.WorkingSet64;cpu_seconds=[double]$process.TotalProcessorTime.TotalSeconds}}
  }
 } elseif($request.operation -eq 'overlay') {
  $reply.operation='overlay';$outcome=Set-CompanionOverlay $request
  foreach($key in $outcome.Keys){$reply[$key]=$outcome[$key]}
 } elseif($request.operation -eq 'document') {
  $reply.operation='document';$outcome=Open-Document $request
  foreach($key in $outcome.Keys){$reply[$key]=$outcome[$key]}
 } else {
 if($request.operation -ne 'open' -or $request.target -isnot [string] -or $request.target.Length -gt 2048 -or -not $request.target.Trim()){throw 'Invalid target'}
 # Reject URLs here: a separately validated URL opener is handled in the application.
 if($request.target -match '^\w+:\/\/'){throw 'Unsupported target'}
 $resolved=Resolve-Target $request.target (Get-AppCatalog)
 $outcome=Open-Target $resolved
 foreach($key in $outcome.Keys){$reply[$key]=$outcome[$key]}
 }
} catch { $reply.status='failed' }
$json=ConvertTo-Json -InputObject $reply -Depth 5 -Compress
[IO.File]::WriteAllText($ResultPath+'.tmp',$json,[Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath ($ResultPath+'.tmp') -Destination $ResultPath -Force
