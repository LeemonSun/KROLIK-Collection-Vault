@echo off
setlocal
set "COMPANION_ROOT=%~dp0"
if not exist "%COMPANION_ROOT%downloads\preview-manifest.json" (
 echo This is the source-only archive. Open project.godot in Godot, or download the full GitHub ZIP.
 pause
 exit /b 1
)
echo Preparing Companion Preview. No developer tools required.
powershell.exe -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; $root=$env:COMPANION_ROOT; $manifest=Get-Content -LiteralPath (Join-Path $root 'downloads/preview-manifest.json') -Raw | ConvertFrom-Json; foreach($p in $manifest.packages){ $dest=Join-Path $root $p.output; $ok=(Test-Path -LiteralPath $dest) -and ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -eq $p.sha256); if(-not $ok){ [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest)) | Out-Null; $targetStream=[IO.File]::Open($dest,[IO.FileMode]::Create); try { foreach($part in $p.parts){ $chunkStream=[IO.File]::OpenRead((Join-Path $root $part)); try { $chunkStream.CopyTo($targetStream) } finally { $chunkStream.Dispose() } } } finally { $targetStream.Dispose() }; if((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne $p.sha256){ throw 'Package integrity check failed. Download and unzip the complete project again.' } } }; $dir=Join-Path $root 'build/windows-preview'; $exe=Join-Path $dir 'Companion_Preview/Companion.exe'; if(-not (Test-Path -LiteralPath $exe) -or (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $manifest.exe_sha256){ Expand-Archive -LiteralPath (Join-Path $root 'build/Companion_Preview_Windows_v0.3.zip') -DestinationPath $dir -Force }; if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $manifest.exe_sha256){ throw 'EXE integrity check failed.' }"
if errorlevel 1 (
 echo Preparation failed. Keep the error above for diagnostics.
 pause
 exit /b 1
)
start "" "%COMPANION_ROOT%build\windows-preview\Companion_Preview\Companion.exe"
endlocal
