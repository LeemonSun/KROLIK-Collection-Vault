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
    try{if($process.Path -ieq $resolved.path -and $process.MainWindowHandle -ne 0){return @{status='visible';name=$resolved.name}}}catch{}
   }
   Start-Sleep -Milliseconds 125
  }
  return @{status='started';name=$resolved.name}
 }
 return @{status=$resolved.kind;choices=$resolved.choices}
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
