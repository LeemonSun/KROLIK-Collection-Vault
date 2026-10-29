param([string]$Desktop,[string]$Access)
$ErrorActionPreference='Stop';$script:checks=0
function Check($value,[string]$label){$script:checks++;if(-not $value){throw $label}}
function Import-Functions($path,$names){
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) ('Parses '+$path)
 foreach($name in $names){$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true);Invoke-Expression ($fn.Extent.Text -replace '^function\s+','function global:')}
}
Import-Functions $Desktop @('Test-AppExecutable','Get-AppId','Get-AppStamp','Get-DiscoveryCatalog','Open-Discovered')
Import-Functions $Access @('Set-ObservedToggle')
function Get-AppIdentity($path){return $null}
$script:opens=0
function Open-Target($record){$script:opens++;return @{status='started'}}
$folder=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $folder
try{
 $path=Join-Path $folder 'ThirdParty.exe';[IO.File]::WriteAllText($path,'synthetic fixture; never launched')
 Check (Test-AppExecutable $path) 'Local third-party EXE is a candidate'
 foreach($name in @('cmd.exe','powershell.exe','setup-client.exe','uninstall.exe','script.ps1')){
  $bad=Join-Path $folder $name;[IO.File]::WriteAllText($bad,'fixture');Check (-not (Test-AppExecutable $bad)) ('Blocked interpreter/installer/nonexe '+$name)
 }
 $id=Get-AppId $path;$stamp=Get-AppStamp $path
 Check ($id -match '^[a-f0-9]{64}$' -and $id -ceq (Get-AppId $path.ToUpperInvariant())) 'Stable case-insensitive opaque app ID'
 $catalog=@(@{name='ThirdParty';path=$path;aliases=@()})
 $reply=Get-DiscoveryCatalog $catalog
 Check ($reply.status -eq 'catalog' -and $reply.apps.Count -eq 1) 'Observed catalog serializes a third-party app'
 $json=ConvertTo-Json $reply -Depth 6
 Check (-not $json.Contains($folder)) 'Model catalog contains no executable path'
 $result=Open-Discovered @{app_id=$id;stamp=$stamp} $catalog
 Check ($result.status -eq 'started' -and $script:opens -eq 1) 'Bound ID maps to trusted catalog path'
 $result=Open-Discovered @{app_id=('a'*64);stamp=$stamp} $catalog
 Check ($result.status -eq 'stale' -and $script:opens -eq 1) 'Unknown ID never launches'
 [IO.File]::AppendAllText($path,'changed')
 $result=Open-Discovered @{app_id=$id;stamp=$stamp} $catalog
 Check ($result.status -eq 'stale' -and $script:opens -eq 1) 'Changed executable stamp prevents stale launch'
 $many=@();for($i=0;$i -lt 100;$i++){$many+=@{name=('App'+$i);path=$path;aliases=@()}}
 $reply=Get-DiscoveryCatalog $many
 Check ($reply.apps.Count -le 96 -and $reply.partial) 'Catalog has bounded size and reports truncation'
 Check ([Text.Encoding]::UTF8.GetByteCount((ConvertTo-Json $reply -Depth 6 -Compress)) -lt 32000) 'Catalog stays within transport budget'
}finally{Remove-Item -LiteralPath $folder -Recurse -Force}
Add-Type -TypeDefinition @'
namespace Windows.Automation {public class TogglePattern {public static object Pattern="toggle";}}
public class State {public int ToggleState=0;}
public class FakeToggle {public State Current=new State();public int Calls=0;public bool Ignore=false;public void Toggle(){Calls++;if(!Ignore)Current.ToggleState=Current.ToggleState==0?1:0;}}
public class FakeElement {public FakeToggle Value=new FakeToggle();public bool TryGetCurrentPattern(object key,ref object value){value=Value;return true;}}
'@
$element=[FakeElement]::new()
Check ((Set-ObservedToggle $element 0 1) -eq 'toggle_set' -and $element.Value.Calls -eq 1) 'Observed OFF→ON one transition'
Check ((Set-ObservedToggle $element 0 1) -eq 'toggle_set' -and $element.Value.Calls -eq 1) 'Already-ON never toggles again'
Check ((Set-ObservedToggle $element 0 0) -eq 'stale' -and $element.Value.Calls -eq 1) 'Mismatched prestate cannot flip switch'
$element.Value.Current.ToggleState=2
Check ((Set-ObservedToggle $element 0 1) -eq 'toggle_unverified' -and $element.Value.Calls -eq 1) 'Indeterminate switch never blindly cycled'
$element.Value.Current.ToggleState=0;$element.Value.Ignore=$true
Check ((Set-ObservedToggle $element 0 1) -eq 'toggle_unverified' -and $element.Value.Calls -eq 2) 'Unchanged switch stops after one effect'
"NATIVE023: $script:checks checks, 0 failures; synthetic native adapters, not Windows applications"
