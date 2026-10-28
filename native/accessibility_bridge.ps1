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
 $queue=[Collections.Generic.Queue[object]]::new()
 $queue.Enqueue([pscustomobject]@{element=$rootElement;depth=0;ancestors=@()})
 $nodes=[Collections.Generic.List[object]]::new();$visited=0;$bytes=0;$partial=$false
 $clock=[Diagnostics.Stopwatch]::StartNew()
 while($queue.Count -and $visited -lt 200 -and $clock.ElapsedMilliseconds -lt 2500) {
  $frame=$queue.Dequeue();$element=$frame.element;$depth=[int]$frame.depth;$visited++
  try {
   $c=$element.Current
   if($c.IsPassword -or $c.IsOffscreen){continue}
   $name=Clip-Text $c.Name 160
   $automationId=Clip-Text $c.AutomationId 64
   $value=$null;$invoke=$null;$select=$null;$expand=$null
   $writable=$element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$value) -and -not $value.Current.IsReadOnly
   $canInvoke=$element.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern,[ref]$invoke)
   $canSelect=$element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$select)
   $canExpand=$element.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$expand)
   $parents=@($frame.ancestors)
   $record=@{id=($element.GetRuntimeId() -join ',');name=$name;type=$c.ControlType.ProgrammaticName;automation_id=$automationId;ancestors=$parents;enabled=$c.IsEnabled;write=$writable;invoke=$canInvoke;select=$canSelect;expand=$canExpand;selected=($canSelect -and $select.Current.IsSelected);expansion=$(if($canExpand){[int]$expand.Current.ExpandCollapseState}else{-1})}
   if($name -or $writable){
    $recordBytes=[Text.Encoding]::UTF8.GetByteCount((ConvertTo-Json -InputObject $record -Depth 6 -Compress))
    if($nodes.Count -lt 90 -and $bytes+$recordBytes -lt 25000){$nodes.Add(@{record=$record;element=$element});$bytes+=$recordBytes+1}else{$partial=$true}
   }
   $crumb=[ordered]@{name=(Clip-Text $name 64);type=$c.ControlType.ProgrammaticName;automation_id=$automationId}
   $nextParents=@($parents)+@($crumb)
   if($nextParents.Count -gt 3){$nextParents=@($nextParents[($nextParents.Count-3)..($nextParents.Count-1)])}
   if($depth -lt 8){
    $child=$walker.GetFirstChild($element);$siblings=0
    while($null -ne $child -and $siblings -lt 90 -and $queue.Count -lt 200 -and $clock.ElapsedMilliseconds -lt 2500){
     $queue.Enqueue([pscustomobject]@{element=$child;depth=($depth+1);ancestors=$nextParents})
     $child=$walker.GetNextSibling($child);$siblings++
    }
    if($null -ne $child){$partial=$true}
   }else{$partial=$true}
  } catch {$partial=$true}
 }
 if($queue.Count){$partial=$true}
 $script:scopeMeta=@{partial=$partial;visited=$visited;elapsed_ms=[int]$clock.ElapsedMilliseconds}
 return $nodes.ToArray()
}
function Test-Descriptor($record,$expected) {
 if($null -eq $expected -or $expected.type -isnot [string] -or $expected.automation_id -isnot [string]){return $false}
 if([string]$record.type -cne [string]$expected.type -or [string]$record.automation_id -cne [string]$expected.automation_id){return $false}
 $actualParents=@($record.ancestors);$expectedParents=@($expected.ancestors)
 if($actualParents.Count -ne $expectedParents.Count -or $expectedParents.Count -gt 3){return $false}
 for($i=0;$i -lt $actualParents.Count;$i++){
  foreach($key in @('name','type','automation_id')){
   if($expectedParents[$i].$key -isnot [string] -or [string]$actualParents[$i].$key -cne [string]$expectedParents[$i].$key){return $false}
  }
 }
 return $true
}
function Is-Risky([string]$name) {
 return $name -match '(?i)send|submit|pay|buy|purchase|delete|remove|install|uninstall|format|reset|confirm|allow|sign.?in|log.?in|отправ|оплат|купить|удал|установ|сброс|формат|подтверд|разреш|войти|发送|提交|支付|购买|删除|安装|卸载|重置|确认|允许|登录'
}
function Read-Eligible($current) {
 # Do not read or descend into passwords or editable single-line fields.
 return -not ($current.IsPassword -or $current.IsOffscreen -or $current.ControlType.ProgrammaticName -in @('ControlType.Edit','ControlType.ComboBox'))
}
function Add-ReadBlock($blocks,$seen,[string]$text,[string]$kind,$budget) {
 $text=(Clip-Text $text 400).Trim()
 if(-not $text -or $seen.ContainsKey($text)){return}
 $size=[Text.Encoding]::UTF8.GetByteCount($text)
 if(($kind -eq 'control' -and @($blocks | Where-Object {$_.kind -eq 'control'}).Count -ge 8) -or $blocks.Count -ge 48 -or $budget.bytes+$size -gt 8000){$budget.partial=$true;return}
 $seen[$text]=$true;$budget.bytes+=$size
 $blocks.Add(@{text=$text;kind=$kind})
}
function Get-ReadBlocks($rootElement) {
 $walker=[Windows.Automation.TreeWalker]::ControlViewWalker
 $queue=[Collections.Generic.Queue[object]]::new();$queue.Enqueue(@($rootElement,0))
 $blocks=[Collections.Generic.List[object]]::new();$seen=@{};$budget=@{bytes=0;partial=$true}
 $clock=[Diagnostics.Stopwatch]::StartNew();$visited=0
 while($queue.Count -and $visited -lt 240 -and $blocks.Count -lt 48 -and $clock.ElapsedMilliseconds -lt 2500) {
  $pair=$queue.Dequeue();$element=$pair[0];$depth=[int]$pair[1];$visited++
  try {
   $c=$element.Current
   if(-not (Read-Eligible $c)){continue}
   $kind=$c.ControlType.ProgrammaticName
   $child=$walker.GetFirstChild($element)
   if($kind -eq 'ControlType.Text') {Add-ReadBlock $blocks $seen $c.Name 'text' $budget}
   elseif($kind -in @('ControlType.Button','ControlType.TabItem','ControlType.MenuItem','ControlType.CheckBox','ControlType.RadioButton','ControlType.Hyperlink')) {Add-ReadBlock $blocks $seen $c.Name 'control' $budget}
   # Only leaf text containers: broad parent ranges could include protected descendants.
   if($null -eq $child -and $kind -in @('ControlType.Document','ControlType.Text')) {
    $pattern=$null
    if($element.TryGetCurrentPattern([Windows.Automation.TextPattern]::Pattern,[ref]$pattern)) {
     $count=0
     foreach($range in $pattern.GetVisibleRanges()) {
      if($count -ge 4){break};$count++
      Add-ReadBlock $blocks $seen ($range.GetText(400)) 'text' $budget
     }
    }
   }
   if($depth -lt 10) {
    $siblings=0
    while($null -ne $child -and $siblings -lt 96 -and $queue.Count -lt 240) {
     $queue.Enqueue(@($child,($depth+1)));$child=$walker.GetNextSibling($child);$siblings++
    }
   }
  }catch{}
 }
 return $blocks.ToArray()
}
try {
 if((Get-Item -LiteralPath $RequestPath).Length -gt 16384){throw 'Request too large'}
 $request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
 if($request.nonce -notmatch '^[a-f0-9]{32}$'){throw 'Invalid nonce'}
 $reply.nonce=$request.nonce
 if($request.operation -notin @('windows','inspect','read','invoke','write')){throw 'Unknown operation'}
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
  if($request.operation -eq 'read') {
   $blocks=@(Get-ReadBlocks $rootElement)
   $null=Assert-Identity $request
   $reply.status='read';$reply.title=(Clip-Text $rootElement.Current.Name 100);$reply.blocks=$blocks;$reply.partial=$true
  }else{
  $nodes=@(Get-ScopedNodes $rootElement)
  if($request.operation -eq 'inspect'){
   $r=$rootElement.Current.BoundingRectangle
   $reply.bounds=@{x=[int]$r.X;y=[int]$r.Y;width=[int]$r.Width;height=[int]$r.Height}
   $null=Assert-Identity $request
   $reply.status='inspected';$reply.title=(Clip-Text $rootElement.Current.Name 100);$reply.nodes=@($nodes | ForEach-Object {$_.record})
   $reply.partial=$script:scopeMeta.partial;$reply.visited=$script:scopeMeta.visited;$reply.elapsed_ms=$script:scopeMeta.elapsed_ms
  }else{
   if([string]$request.element_id -notmatch '^-?\d+(,-?\d+){1,30}$' -or $request.element_name -isnot [string]){throw 'Invalid element'}
   $matches=@($nodes | Where-Object {$_.record.id -ceq $request.element_id -and $_.record.name -ceq $request.element_name -and (Test-Descriptor $_.record $request.element_descriptor)})
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
 }
} catch {$reply.status='failed'}
$json=ConvertTo-Json -InputObject $reply -Depth 10 -Compress
if([Text.Encoding]::UTF8.GetByteCount($json) -gt 32000){$json=ConvertTo-Json @{nonce=$reply.nonce;status='too_large'} -Compress}
[IO.File]::WriteAllText($ResultPath+'.tmp',$json,[Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath ($ResultPath+'.tmp') -Destination $ResultPath -Force
