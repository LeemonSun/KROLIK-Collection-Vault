param([string]$Helper)
$ErrorActionPreference='Stop'
$script:checks=0
function Check($value,[string]$label){$script:checks++;if(-not $value){throw $label}}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($Helper,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'VPN helper parses'
$function=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-Profiles'},$true)
Invoke-Expression $function.Extent.Text
$script:mode='normal';$script:scopes=@()
function Get-VpnConnection {
 param([switch]$AllUserConnection,[string]$ErrorAction)
 $script:scopes+=([bool]$AllUserConnection)
 if($script:mode -eq 'overflow'){
  for($i=0;$i -lt 33;$i++){[pscustomobject]@{Name="Profile$i";ConnectionStatus='Disconnected';Secret='NOT_RETURNED'}}
 }elseif($script:mode -ne 'empty'){
  [pscustomobject]@{Name='Work';ConnectionStatus=$(if($AllUserConnection){'Connected'}else{'Disconnected'});ServerAddress='NOT_RETURNED';Secret='NOT_RETURNED'}
 }
}
$items=@(Get-Profiles)
Check ($items.Count -eq 2) 'User and all-user profiles preserved separately'
Check ($script:scopes.Count -eq 2 -and -not $script:scopes[0] -and $script:scopes[1]) 'Both profile scopes queried'
Check (-not $items[0].connected -and $items[1].connected) 'Connected state reflects system status'
Check (-not $items[0].shared -and $items[1].shared) 'Shared flag preserved'
Check (-not ((ConvertTo-Json $items) -match 'NOT_RETURNED')) 'No server address or credentials in inventory'
$script:mode='empty';Check (@(Get-Profiles).Count -eq 0) 'Empty inventory remains empty'
$script:mode='overflow';$blocked=$false;try{$null=Get-Profiles}catch{$blocked=$true}
Check $blocked 'Inventory limit enforced'
"VPN_PROTOCOL022: $script:checks checks, 0 failures; synthetic provider, not Windows connection"
