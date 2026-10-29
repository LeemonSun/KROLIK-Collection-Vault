param([Parameter(Mandatory=$true)][string]$RequestPath,[Parameter(Mandatory=$true)][string]$ResultPath)
$ErrorActionPreference='Stop'
$reply=@{status='failed';nonce=''}
function Get-Profiles {
 $items=[Collections.Generic.List[object]]::new()
 foreach($shared in @($false,$true)){
  $profiles=if($shared){Get-VpnConnection -AllUserConnection -ErrorAction Stop}else{Get-VpnConnection -ErrorAction Stop}
  foreach($p in $profiles){
   if($items.Count -ge 32){throw 'Too many profiles'}
   $items.Add(@{name=[string]$p.Name;shared=$shared;connected=([string]$p.ConnectionStatus -eq 'Connected')})
  }
 }
 return $items.ToArray()
}
try{
 if((Get-Item -LiteralPath $RequestPath).Length -gt 4096){throw 'Request too large'}
 $request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
 if($request.nonce -notmatch '^[a-f0-9]{32}$'){throw 'Invalid nonce'};$reply.nonce=$request.nonce
 if($request.operation -ne 'vpn_connect'){throw 'Unknown operation'}
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){$reply.status='unsupported'}else{
  $profiles=@(Get-Profiles)
  if($request.name){$profiles=@($profiles | Where-Object {$_.name -ceq [string]$request.name})}
  if($profiles.Count -eq 0){$reply.status='vpn_missing'}
  elseif($profiles.Count -ne 1){$reply.status='vpn_ambiguous'}
  elseif($profiles[0].connected){$reply.status='vpn_connected'}
  else{
   $profile=$profiles[0]
   if($profile.name.Length -gt 128 -or $profile.name -match '["\x00-\x1f]'){throw 'Invalid profile'}
   $book=if($profile.shared){Join-Path $env:ProgramData 'Microsoft/Network/Connections/Pbk/rasphone.pbk'}else{Join-Path $env:APPDATA 'Microsoft/Network/Connections/Pbk/rasphone.pbk'}
   if(-not (Test-Path -LiteralPath $book) -or $book -match '["\x00-\x1f]'){throw 'Phonebook missing'}
   $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=Join-Path $env:WINDIR 'System32/rasdial.exe'
   $info.UseShellExecute=$false;$info.CreateNoWindow=$true
   # Profile and phonebook are sourced locally; never accept shell commands or credentials.
   $info.Arguments='"'+$profile.name+'" /PHONEBOOK:"'+$book+'"'
   $child=[Diagnostics.Process]::Start($info)
   try{
    if(-not $child.WaitForExit(8000)){try{$child.Kill()}catch{};$reply.status='vpn_timeout'}else{
     $reply.status='vpn_unverified'
     for($i=0;$i -lt 4;$i++){
      $fresh=@(Get-Profiles | Where-Object {$_.name -ceq $profile.name -and $_.shared -eq $profile.shared})
      if($fresh.Count -eq 1 -and $fresh[0].connected){$reply.status='vpn_connected';break}
      Start-Sleep -Milliseconds 250
     }
    }
   }finally{$child.Dispose()}
  }
 }
}catch{$reply.status='failed'}
$json=ConvertTo-Json -InputObject $reply -Depth 4 -Compress
[IO.File]::WriteAllText($ResultPath+'.tmp',$json,[Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath ($ResultPath+'.tmp') -Destination $ResultPath -Force
