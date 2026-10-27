param([Parameter(Mandatory=$true)][string]$Bridge)
$ErrorActionPreference='Stop';$checks=0
function Assert($ok,[string]$label){$script:checks++;if(-not $ok){throw $label}}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($Bridge,[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0) 'PowerShell syntax'
foreach($fn in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){Invoke-Expression $fn.Extent.Text}
$native=$ast.FindAll({param($n)$n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.Contains('public static class LeemonAccess')},$true)[0].Value
Add-Type -TypeDefinition $native
foreach($label in @('Send','Delete file','Отправить','Купить','提交','删除')){Assert (Is-Risky $label) ('Sensitive control '+$label)}
foreach($label in @('Insert','Search','Вставка','Поиск','插入')){Assert (-not (Is-Risky $label)) ('Routine control '+$label)}
Assert ((Clip-Text ('x'*200) 160).Length -eq 160) 'Labels bounded'
$folder=Join-Path ([IO.Path]::GetTempPath()) ('Leemon-access-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $folder
try {
 $request=Join-Path $folder 'request.json';$result=Join-Path $folder 'result.json'
 @{nonce=('a'*32);operation='windows';owner_pid=$PID} | ConvertTo-Json | Set-Content -LiteralPath $request -Encoding UTF8
 & $Bridge -RequestPath $request -ResultPath $result
 $reply=Get-Content -LiteralPath $result -Raw | ConvertFrom-Json
 Assert ($reply.nonce -eq ('a'*32)) 'Nonce roundtrip'
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){Assert ($reply.status -eq 'unsupported') 'Unsupported host does not simulate a Windows action'}
 @{nonce=('a'*32);operation='shell.exec';text='calc'} | ConvertTo-Json | Set-Content -LiteralPath $request -Encoding UTF8
 & $Bridge -RequestPath $request -ResultPath $result
 $reply=Get-Content -LiteralPath $result -Raw | ConvertFrom-Json
 Assert ($reply.status -eq 'failed') 'Unknown effects fail closed'
}finally{Remove-Item -LiteralPath $folder -Recurse -Force}
Write-Output "ACCESS_BRIDGE_TESTS: $checks checks PASS; C# compiled, pure logic/protocol; Windows API not executed"
