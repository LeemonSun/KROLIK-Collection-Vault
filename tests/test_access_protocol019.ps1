param([string]$Helper)
$ErrorActionPreference='Stop'
$script:checks=0
function Check($value,[string]$label){$script:checks++;if(-not $value){throw $label}}
# Extract only local pure/traversal function definitions. Never run the bridge entrypoint.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($Helper,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'Native helper parses'
foreach($name in @('Clip-Text','Get-ScopedNodes','Test-Descriptor')){
 $function=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 if($null -eq $function){throw "Missing function $name"}
 Invoke-Expression $function.Extent.Text
}
# Deliberately synthetic UIA types: exercises our traversal, not Windows providers.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
namespace Windows.Automation {
 public class Kind {public string ProgrammaticName; public Kind(string n){ProgrammaticName=n;}}
 public class CurrentData {public string Name;public string AutomationId;public Kind ControlType;public bool IsPassword=false;public bool IsOffscreen=false;public bool IsEnabled=true;}
 public class PatternData {public bool IsReadOnly=false;public bool IsSelected=false;public int ExpandCollapseState=0;}
 public class Pattern {public PatternData Current=new PatternData();}
 public class TogglePattern {public static object Pattern="toggle";}
 public class ValuePattern {public static object Pattern="value";}
 public class InvokePattern {public static object Pattern="invoke";}
 public class SelectionItemPattern {public static object Pattern="select";}
 public class ExpandCollapsePattern {public static object Pattern="expand";}
 public class Element {
  public CurrentData Current=new CurrentData();public List<Element> Children=new List<Element>();public Element Parent;public bool Writable=false;public int Id;
  public Element(string name,string id,int runtime){Current.Name=name;Current.AutomationId=id;Current.ControlType=new Kind("ControlType.Pane");Id=runtime;}
  public Element Add(Element child){child.Parent=this;Children.Add(child);return child;}
  public int[] GetRuntimeId(){return new int[]{1,Id};}
  public bool TryGetCurrentPattern(object kind,ref object pattern){pattern=new Pattern();return Writable && (string)kind=="value";}
 }
 public class TreeWalker {
  public static TreeWalker ControlViewWalker=new TreeWalker();
  public Element GetFirstChild(Element e){return e.Children.Count==0?null:e.Children[0];}
  public Element GetNextSibling(Element e){if(e.Parent==null)return null;int i=e.Parent.Children.IndexOf(e)+1;return i<e.Parent.Children.Count?e.Parent.Children[i]:null;}
 }
}
'@
function Element([string]$name,[string]$id,[int]$runtime){return [Windows.Automation.Element]::new($name,$id,$runtime)}
$root=Element 'Synthetic app' 'root' 1
$left=$root.Add((Element 'Editor' 'editor' 2));$right=$root.Add((Element 'Player' 'player' 3))
$field=$left.Add((Element 'Text' 'text' 4));$field.Writable=$true
$null=$right.Add((Element 'Text' 'text' 5))
$secret=$root.Add((Element 'Password container' 'password' 6));$secret.Current.IsPassword=$true
$null=$secret.Add((Element 'SECRET_DESCENDANT' 'secret' 7))
$nodes=@(Get-ScopedNodes $root)
Check ($nodes.Count -eq 5) 'Password subtree is not observed'
Check (-not (@($nodes | Where-Object {$_.record.name -eq 'SECRET_DESCENDANT'}).Count)) 'No protected descendant name'
$rootRecord=@($nodes | Where-Object {$_.record.id -eq '1,1'})[0].record
$rootExpected=($rootRecord | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
Check (Test-Descriptor $rootRecord $rootExpected) 'Empty ancestor array roundtrip'
$record=@($nodes | Where-Object {$_.record.id -eq '1,4'})[0].record
Check ($record.write -and $record.automation_id -eq 'text') 'Native capability and AutomationId retained'
Check ($record.ancestors.Count -eq 2 -and $record.ancestors[1].name -eq 'Editor') 'Context follows actual traversal parents'
$expected=($record | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
Check (Test-Descriptor $record $expected) 'Exact serialized descriptor matches'
$expected.ancestors[1].name='Player';Check (-not (Test-Descriptor $record $expected)) 'Changed parent rejected'
$expected.ancestors[1].name='Editor';$expected.type='ControlType.Button';Check (-not (Test-Descriptor $record $expected)) 'Changed role rejected'
$expected.type=$record.type;$expected.automation_id='other';Check (-not (Test-Descriptor $record $expected)) 'Changed AutomationId rejected'
Check (-not (Test-Descriptor $record $null)) 'Missing descriptor rejected'
Check (-not $script:scopeMeta.partial) 'Small complete fixture accurately reported'
$wide=Element ('W'*160) ('A'*64) 10
for($i=0;$i -lt 250;$i++){$null=$wide.Add((Element ('N'*160) ('I'*64) ($i+11)))}
$nodes=@(Get-ScopedNodes $wide)
Check ($script:scopeMeta.partial -and $script:scopeMeta.visited -le 200) 'Wide observation bounded and explicitly partial'
Check ($nodes.Count -le 90) 'Node count bounded'
$json=ConvertTo-Json -InputObject @{status='inspected';nodes=@($nodes | ForEach-Object {$_.record})} -Depth 10 -Compress
Check ([Text.Encoding]::UTF8.GetByteCount($json) -lt 32000) 'Context stays inside IPC byte limit'
$deep=Element 'Deep' 'deep' 300;$cursor=$deep
for($i=0;$i -lt 12;$i++){$cursor=$cursor.Add((Element ('section'+$i) ('id'+$i) ($i+301)))}
$nodes=@(Get-ScopedNodes $deep)
Check ($script:scopeMeta.partial -and $nodes.Count -le 9) 'Depth limit disclosed'
Check (@($nodes | Where-Object {$_.record.ancestors.Count -gt 3}).Count -eq 0) 'Ancestor context capped at three'
"ACCESS_PROTOCOL019: $script:checks checks, 0 failures; real PowerShell with synthetic traversal types, not real Windows UIA"

$browser=Element 'Browser' 'browser' 800
$tab=$browser.Add((Element 'SoundCloud' 'tab' 801));$tab.Current.ControlType.ProgrammaticName='ControlType.TabItem';$tab.Current.IsOffscreen=$true
$document=$browser.Add((Element 'PAGE_PRIVATE_TEXT' 'page' 802));$document.Current.ControlType.ProgrammaticName='ControlType.Document'
$null=$document.Add((Element 'HIDDEN_PAGE_DESCENDANT' 'child' 803))
$chrome=@(Get-ScopedNodes $browser $true)
Check (@($chrome | Where-Object {$_.record.name -eq 'SoundCloud'}).Count -eq 1) 'Chrome search can inspect an offscreen tab'
Check (@($chrome | Where-Object {$_.record.name -in @('PAGE_PRIVATE_TEXT','HIDDEN_PAGE_DESCENDANT')}).Count -eq 0) 'Chrome search skips page document and descendants'
"CHROME022: 2 additional checks, 0 failures; synthetic tree, not Windows"
