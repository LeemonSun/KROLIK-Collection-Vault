param([Parameter(Mandatory=$true)][string]$Bridge)
$ErrorActionPreference='Stop'
$script:checks=0
function Assert($ok,[string]$message){$script:checks++;if(-not $ok){throw $message}}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($Bridge,[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0) 'PowerShell syntax'
foreach($fn in $ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
 Invoke-Expression $fn.Extent.Text
}
$catalog=@(
 @{name='Notepad';aliases=@('блокнот','记事本');path='C:\Windows\System32\notepad.exe'},
 @{name='Steam';aliases=@();path='C:\Steam\steam.exe'},
 @{name='Opera';aliases=@();path='C:\Opera\launcher.exe'},
 @{name='Opera GX';aliases=@();path='C:\OperaGX\launcher.exe'}
)
Assert ((Normalize-Name 'Блокнот!') -eq 'блокнот') 'Unicode normalization'
foreach($name in @('Notepad','блокнот','记事本')){
 $result=Resolve-Target $name $catalog
 Assert ($result.kind -eq 'app' -and $result.path.EndsWith('notepad.exe')) ('Resolve '+$name)
}
Assert ((Resolve-Target 'стим' $catalog).name -eq 'Steam') 'Russian app alias'
Assert ((Resolve-Target 'Opera' $catalog).name -eq 'Opera') 'Exact name takes priority'
Assert ((Resolve-Target 'Ope' $catalog).kind -eq 'ambiguous') 'Ambiguous targets do not launch'
Assert ((Resolve-Target 'something missing' $catalog).kind -eq 'missing') 'Unknown target'
foreach($name in @('cmd /c calc','powershell -EncodedCommand AAAA','notepad; calc','$(whoami)','https://example.org')){
 Assert ((Resolve-Target $name $catalog).kind -eq 'missing') ('No shell interpretation: '+$name)
}
foreach($name in @('проводник','explorer','文件资源管理器')){
 Assert ((Resolve-Target $name $catalog).kind -eq 'folder') ('Explorer alias '+$name)
}
# Test the actual request/result protocol and real process metrics without Windows COM.
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('companion bridge '+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temporary
try {
 $request=Join-Path $temporary 'request.json';$result=Join-Path $temporary 'result.json'
 $nonce='a'*32
 @{nonce=$nonce;operation='metrics';pids=@($PID)} | ConvertTo-Json | Set-Content -LiteralPath $request -Encoding UTF8
 & $Bridge -RequestPath $request -ResultPath $result
 $reply=Get-Content -LiteralPath $result -Raw | ConvertFrom-Json
 Assert ($reply.nonce -eq $nonce -and $reply.status -eq 'ok' -and $reply.operation -eq 'metrics') 'Actual protocol nonce and operation'
 Assert ($reply.items.Count -eq 1 -and $reply.items[0].bytes -gt 0 -and $reply.items[0].cpu_seconds -ge 0) 'Actual process RAM and CPU time'
 @{nonce='bad';operation='metrics';pids=@($PID)} | ConvertTo-Json | Set-Content -LiteralPath $request -Encoding UTF8
 & $Bridge -RequestPath $request -ResultPath $result
 $reply=Get-Content -LiteralPath $result -Raw | ConvertFrom-Json
 Assert ($reply.status -eq 'failed') 'Invalid request rejected'
 Assert (-not (Test-Path -LiteralPath ($result+'.tmp'))) 'Atomic result has no leftover temporary file'
} finally {Remove-Item -LiteralPath $temporary -Recurse -Force}
Write-Output "DESKTOP_BRIDGE_TESTS: $script:checks checks PASS; resolver/protocol/metrics. Windows COM launching not exercised."
