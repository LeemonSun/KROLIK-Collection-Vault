param([Parameter(Mandatory=$true)][string]$RequestPath,[Parameter(Mandatory=$true)][string]$ResultPath)
$ErrorActionPreference='Stop'
$reply=@{status='failed';nonce=''}
function Clip-Text([string]$text,[int]$limit=160){if($text.Length -gt $limit){return $text.Substring(0,$limit)};return $text}
function Assert-Identity($request) {
 if([string]$request.handle -notmatch '^\d{1,19}$' -or [string]$request.target_pid -notmatch '^\d{1,10}$' -or [string]$request.started -notmatch '^\d{1,19}$'){throw 'Invalid identity'}
 $window=[IntPtr]::new([long]$request.handle);$ownerId=[uint32]0
 $null=[LeemonAccess]::GetWindowThreadProcessId($window,[ref]$ownerId)
 if($ownerId -ne [int]$request.target_pid -or -not [LeemonAccess]::IsWindow($window)){throw 'Window changed'}
 $process=Get-Process -Id $ownerId
 if([string]$process.StartTime.ToUniversalTime().Ticks -ne [string]$request.started -or $ownerId -eq [int]$request.owner_pid){throw 'Process changed'}
 return $window
}
function Get-WindowIdentity($window) {
 $ownerId=[uint32]0;$null=[LeemonAccess]::GetWindowThreadProcessId($window,[ref]$ownerId)
 $process=Get-Process -Id $ownerId
 $text=[Text.StringBuilder]::new(256);$null=[LeemonAccess]::GetWindowText($window,$text,256)
 return @{handle=[string]$window.ToInt64();target_pid=[int]$ownerId;started=[string]$process.StartTime.ToUniversalTime().Ticks;title=(Clip-Text $text.ToString() 100);app=$process.ProcessName}
}
function Get-ScopedNodes($rootElement) {
 $walker=[Windows.Automation.TreeWalker]::ControlViewWalker
 $queue=[Collections.Generic.Queue[object]]::new();$queue.Enqueue(@($rootElement,0));$nodes=[Collections.Generic.List[object]]::new()
 $visited=0
 while($queue.Count -and $visited -lt 200 -and $nodes.Count -lt 90) {
  $pair=$queue.Dequeue();$element=$pair[0];$depth=[int]$pair[1];$visited++
  try {
   $c=$element.Current
   if($c.IsPassword -or $c.IsOffscreen){continue}
   $name=Clip-Text $c.Name 160
   $value=$null;$invoke=$null;$select=$null;$expand=$null
   $writable=$element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$value) -and -not $value.Current.IsReadOnly
   $canInvoke=$element.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern,[ref]$invoke)
   $canSelect=$element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$select)
   $canExpand=$element.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$expand)
   $record=@{id=($element.GetRuntimeId() -join ',');name=$name;type=$c.ControlType.ProgrammaticName;enabled=$c.IsEnabled;write=$writable;invoke=$canInvoke;select=$canSelect;expand=$canExpand;selected=($canSelect -and $select.Current.IsSelected);expansion=$(if($canExpand){[int]$expand.Current.ExpandCollapseState}else{-1})}
   if($name -or $writable){$nodes.Add(@{record=$record;element=$element})}
   if($depth -lt 8){
    $child=$walker.GetFirstChild($element);$siblings=0
    while($null -ne $child -and $siblings -lt 90 -and $queue.Count -lt 200){$queue.Enqueue(@($child,($depth+1)));$child=$walker.GetNextSibling($child);$siblings++}
   }
  } catch {}
 }
 return $nodes.ToArray()
}
function Is-Risky([string]$name) {
 return $name -match '(?i)send|submit|pay|buy|purchase|delete|remove|install|uninstall|format|reset|confirm|allow|sign.?in|log.?in|отправ|оплат|купить|удал|установ|сброс|формат|подтверд|разреш|войти|发送|提交|支付|购买|删除|安装|卸载|重置|确认|允许|登录'
}
try {
 if((Get-Item -LiteralPath $RequestPath).Length -gt 16384){throw 'Request too large'}
 $request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
 if($request.nonce -notmatch '^[a-f0-9]{32}$'){throw 'Invalid nonce'}
 $reply.nonce=$request.nonce
 if($request.operation -notin @('windows','inspect','invoke','write')){throw 'Unknown operation'}
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){$reply.status='unsupported'}else{
 Add-Type -AssemblyName UIAutomationClient
 Add-Type -AssemblyName UIAutomationTypes
 Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class LeemonAccess {
 public delegate bool EnumProc(IntPtr hwnd, IntPtr param);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback,IntPtr param);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd,StringBuilder text,int max);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint ownerId);
}
'@
 if($request.operation -eq 'windows'){
  $windows=[Collections.Generic.List[object]]::new()
  $callback=[LeemonAccess+EnumProc]{param($window,$unused)
   try {if([LeemonAccess]::IsWindowVisible($window)){
    $identity=Get-WindowIdentity $window
    if($identity.target_pid -ne [int]$request.owner_pid -and $identity.title -and $windows.Count -lt 24){$windows.Add($identity)}
   }}catch{}
   return $true
  }
  $null=[LeemonAccess]::EnumWindows($callback,[IntPtr]::Zero)
  $reply.status='windows';$reply.windows=$windows.ToArray()
 }else{
  $window=Assert-Identity $request
  $rootElement=[Windows.Automation.AutomationElement]::FromHandle($window)
  $nodes=@(Get-ScopedNodes $rootElement)
  if($request.operation -eq 'inspect'){
   $reply.status='inspected';$reply.title=(Clip-Text $rootElement.Current.Name 100);$reply.nodes=@($nodes | ForEach-Object {$_.record})
  }else{
   if([string]$request.element_id -notmatch '^-?\d+(,-?\d+){1,30}$' -or $request.element_name -isnot [string]){throw 'Invalid element'}
   $matches=@($nodes | Where-Object {$_.record.id -ceq $request.element_id -and $_.record.name -ceq $request.element_name})
   if($matches.Count -ne 1){$reply.status='stale'}else{
    $item=$matches[0];$element=$item.element;$record=$item.record
    $null=Assert-Identity $request
    if(-not $element.Current.IsEnabled -or $element.Current.IsPassword -or $element.Current.IsOffscreen){throw 'Unavailable element'}
    if($request.operation -eq 'write'){
     $process=Get-Process -Id ([int]$request.target_pid)
     if($process.ProcessName -match '^(?i:cmd|powershell|pwsh|windowsterminal|conhost|bash|wsl|regedit)$'){throw 'Interpreter input blocked'}
     if($request.text -isnot [string] -or $request.text.Length -gt 2000 -or $request.text -match '[\x00-\x08\x0b\x0c\x0e-\x1f]'){throw 'Invalid text'}
     $pattern=$null
     if(-not $element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$pattern) -or $pattern.Current.IsReadOnly){$reply.status='write_unsupported'}else{
      $before=$pattern.Current.Value
      if($before.Length -gt 8000){throw 'Field too large'}
      if($before -and -not $request.append){$reply.status='not_empty'}else{
       $after=if($request.append){$before+$request.text}else{$request.text}
       if($pattern.Current.Value -cne $before){throw 'Field changed'}
       $pattern.SetValue($after)
       $reply.status=if($pattern.Current.Value -ceq $after){'written'}else{'write_unverified'}
      }
     }
    }elseif((Is-Risky $record.name) -and $request.confirmed -ne $true){$reply.status='confirmation_required'}else{
     $pattern=$null
     $requestedPattern=[string]$request.pattern
     if($requestedPattern -and $requestedPattern -notin @('select','expand','invoke')){throw 'Unsupported pattern'}
     if(((-not $requestedPattern) -or $requestedPattern -eq 'select') -and $record.select -and $element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$pattern)){$pattern.Select();$reply.status='selected'}
     elseif(((-not $requestedPattern) -or $requestedPattern -eq 'expand') -and $record.expand -and $element.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$pattern)){$pattern.Expand();$reply.status='expanded'}
     elseif(((-not $requestedPattern) -or $requestedPattern -eq 'invoke') -and $record.invoke -and $element.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern,[ref]$pattern)){$pattern.Invoke();$reply.status='invoked'}
     else{$reply.status='invoke_unsupported'}
    }
   }
  }
 }
 }
} catch {$reply.status='failed'}
$json=ConvertTo-Json -InputObject $reply -Depth 7 -Compress
if([Text.Encoding]::UTF8.GetByteCount($json) -gt 32000){$json=ConvertTo-Json @{nonce=$reply.nonce;status='too_large'} -Compress}
[IO.File]::WriteAllText($ResultPath+'.tmp',$json,[Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath ($ResultPath+'.tmp') -Destination $ResultPath -Force
