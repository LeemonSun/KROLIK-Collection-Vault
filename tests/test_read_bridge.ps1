param([Parameter(Mandatory=$true)][string]$Bridge)
$ErrorActionPreference='Stop';$checks=0
function Assert($ok,[string]$label){$script:checks++;if(-not $ok){throw $label}}
# An isolated UIA-shaped tree exercises the real walker without a Windows desktop.
Add-Type -TypeDefinition @'
namespace Windows.Automation {
 public class FixtureType { public string ProgrammaticName; }
 public class FixtureCurrent { public bool IsPassword; public bool IsOffscreen; public string Name; public FixtureType ControlType; }
 public class FixtureRange { public string Text; public string GetText(int maximum) { if(maximum<0)throw new System.Exception("Unbounded read");return Text.Substring(0,System.Math.Min(Text.Length,maximum)); } }
 public class FixturePattern { public FixtureRange[] Ranges; public int Reads; public FixtureRange[] GetVisibleRanges(){Reads++;return Ranges;} }
 public class FixtureElement {
  public FixtureCurrent Current; public FixtureElement Child; public FixtureElement Next; public FixturePattern Content;
  public bool TryGetCurrentPattern(object ignored,out object pattern){pattern=Content;return Content!=null;}
 }
 public class TreeWalker {
  public static TreeWalker ControlViewWalker=new TreeWalker();
  public FixtureElement GetFirstChild(FixtureElement e){return e.Child;}
  public FixtureElement GetNextSibling(FixtureElement e){return e.Next;}
 }
 public class TextPattern { public static object Pattern=new object(); }
}
'@
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($Bridge,[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0) 'Helper parses'
foreach($fn in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){Invoke-Expression $fn.Extent.Text}
function Make-Node([string]$name,[string]$type='Text',[string]$content='') {
 $node=[Windows.Automation.FixtureElement]::new()
 $node.Current=[Windows.Automation.FixtureCurrent]::new();$node.Current.Name=$name
 $node.Current.ControlType=[Windows.Automation.FixtureType]::new();$node.Current.ControlType.ProgrammaticName='ControlType.'+$type
 if($content){$node.Content=[Windows.Automation.FixturePattern]::new();$range=[Windows.Automation.FixtureRange]::new();$range.Text=$content;$node.Content.Ranges=@($range)}
 return $node
}
$root=Make-Node 'Demo' 'Window';$public=Make-Node 'Budget: 42 credits.'
$secret=Make-Node 'SECRET PASSWORD' 'Text';$secret.Current.IsPassword=$true;$secret.Child=Make-Node 'SECRET CHILD'
$edit=Make-Node 'PRIVATE EDIT VALUE' 'Edit';$edit.Child=Make-Node 'PRIVATE EDIT CHILD'
$hidden=Make-Node 'OFFSCREEN';$hidden.Current.IsOffscreen=$true
$document=Make-Node '' 'Document' ('Visible document text. '+'x'*600)
$parent=Make-Node '' 'Document' 'BROAD PARENT SECRET';$parent.Child=Make-Node 'SAFE CHILD'
$root.Child=$public;$public.Next=$secret;$secret.Next=$edit;$edit.Next=$hidden;$hidden.Next=$document;$document.Next=$parent
$blocks=@(Get-ReadBlocks $root);$text=($blocks.text -join "`n")
Assert ($text.Contains('Budget: 42 credits.')) 'Visible static text read'
Assert ($text.Contains('Visible document text.')) 'Leaf visible TextPattern ranges read'
Assert (-not $text.Contains('SECRET')) 'Passwords and broad parent ranges excluded'
Assert (-not $text.Contains('PRIVATE')) 'Editable fields and their descendants excluded'
Assert (-not $text.Contains('OFFSCREEN')) 'Offscreen text excluded'
Assert ($text.Contains('SAFE CHILD') -and $parent.Content.Reads -eq 0) 'Container pattern cannot bypass protected-descendant policy'
Assert ($document.Content.Reads -eq 1 -and @($blocks | Where-Object {$_.text.Length -gt 400}).Count -eq 0) 'TextPattern read is bounded'
$bag=[Collections.Generic.List[object]]::new();$seen=@{};$budget=@{bytes=0;partial=$true}
for($i=0;$i -lt 100;$i++){Add-ReadBlock $bag $seen ('Button '+$i) 'control' $budget}
Assert ($bag.Count -eq 8) 'Toolbar controls cannot consume entire evidence budget'
for($i=0;$i -lt 100;$i++){Add-ReadBlock $bag $seen (('字'*399)+$i) 'text' $budget}
Assert ($budget.bytes -le 8000 -and $bag.Count -le 48) 'CJK output bounded by bytes and rows'
$before=$bag.Count;Add-ReadBlock $bag $seen 'Button 0' 'control' $budget
Assert ($bag.Count -eq $before) 'Duplicate excerpts omitted'
Write-Output "READ_BRIDGE_TESTS: $checks checks PASS; synthetic provider tree, no actual Windows UIA"
