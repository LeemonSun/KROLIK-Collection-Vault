[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [string]$OutputRoot = '',
    [int[]]$Agents = @(220, 300, 500),
    [ValidateRange(1, 10)]
    [int]$Repeat = 3,
    [switch]$SkipLod,
    [switch]$SkipDependencyInstall,
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$GodotVersion = '4.7.2'
$GodotArchiveSha256 = '731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953'
$GodotArchiveName = "Godot_v$GodotVersion-stable_win64.exe.zip"
$GodotDownloadUrl = "https://github.com/godotengine/godot/releases/download/$GodotVersion-stable/$GodotArchiveName"
$SoftwareRendererPatterns = @(
    'Microsoft Basic Render Driver',
    'llvmpipe',
    'SwiftShader',
    'software renderer'
)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RuntimeRoot = Join-Path $RepoRoot 'runtime_godot'
$GeneratedPackageRoot = Join-Path $RuntimeRoot '.target_benchmark_core'
$ManifestResPath = 'res://.target_benchmark_core/exports/runtime/ci_core_slice/manifest.json'
$ManifestDiskPath = Join-Path $GeneratedPackageRoot 'exports/runtime/ci_core_slice/manifest.json'
$CacheRoot = Join-Path $RepoRoot '.target_benchmark'

$HostedBaselines = @(
    [pscustomobject]@{ mode = 'no_lod'; agents = 220; fps = 6.96; peak_mib = 603.45; run = '34933824299' },
    [pscustomobject]@{ mode = 'no_lod'; agents = 300; fps = 6.12; peak_mib = 775.41; run = '34933824299' },
    [pscustomobject]@{ mode = 'no_lod'; agents = 500; fps = 3.42; peak_mib = 1172.12; run = '34933824299' },
    [pscustomobject]@{ mode = 'lod'; agents = 500; fps = 11.98; peak_mib = 1105.21; run = '34935517813' }
)

function Write-Section([string]$Text) {
    Write-Host ''
    Write-Host "=== $Text ==="
}

function Assert-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label missing: $Path"
    }
}

function Get-GitHead {
    try {
        $value = (& git -C $RepoRoot rev-parse HEAD 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $value) { return $value }
    } catch {}
    return 'unknown'
}

function Get-PythonVersion {
    try {
        $value = (& python --version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $value) { return $value }
    } catch {}
    return 'unknown'
}

function Get-SafeCim([string]$ClassName) {
    try { return @(Get-CimInstance -ClassName $ClassName -ErrorAction Stop) } catch { return @() }
}

function Get-SystemSnapshot {
    $os = @(Get-SafeCim 'Win32_OperatingSystem' | Select-Object -First 1)
    $cpu = @(Get-SafeCim 'Win32_Processor' | Select-Object -First 1)
    $computer = @(Get-SafeCim 'Win32_ComputerSystem' | Select-Object -First 1)
    $video = @(Get-SafeCim 'Win32_VideoController' | ForEach-Object {
        [pscustomobject]@{
            name = [string]$_.Name
            driver_version = [string]$_.DriverVersion
            adapter_ram_bytes = if ($null -ne $_.AdapterRAM) { [long]$_.AdapterRAM } else { 0 }
        }
    })
    $powerPlan = 'unknown'
    try {
        $powerPlan = (& powercfg /getactivescheme 2>$null | Out-String).Trim()
    } catch {}

    $totalRam = 0L
    if ($computer.Count -gt 0 -and $null -ne $computer[0].TotalPhysicalMemory) {
        $totalRam = [long]$computer[0].TotalPhysicalMemory
    }

    return [pscustomobject]@{
        captured_utc = [DateTime]::UtcNow.ToString('o')
        machine = $env:COMPUTERNAME
        os = if ($os.Count -gt 0) { [string]$os[0].Caption } else { 'unknown' }
        os_version = if ($os.Count -gt 0) { [string]$os[0].Version } else { 'unknown' }
        os_build = if ($os.Count -gt 0) { [string]$os[0].BuildNumber } else { 'unknown' }
        cpu = if ($cpu.Count -gt 0) { ([string]$cpu[0].Name).Trim() } else { 'unknown' }
        physical_cores = if ($cpu.Count -gt 0) { [int]$cpu[0].NumberOfCores } else { 0 }
        logical_processors = if ($cpu.Count -gt 0) { [int]$cpu[0].NumberOfLogicalProcessors } else { 0 }
        total_ram_bytes = $totalRam
        total_ram_gib = [math]::Round($totalRam / 1GB, 2)
        video_controllers = $video
        power_plan = $powerPlan
        python = Get-PythonVersion
        git_head = Get-GitHead
    }
}

function Get-OutputRoot {
    if ($OutputRoot) {
        $candidate = $OutputRoot
        if (-not [IO.Path]::IsPathRooted($candidate)) {
            $candidate = Join-Path $RepoRoot $candidate
        }
        New-Item -ItemType Directory -Force -Path $candidate | Out-Null
        return (Resolve-Path $candidate).Path
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $candidate = Join-Path $RepoRoot "target_benchmark_artifacts/$stamp"
    New-Item -ItemType Directory -Force -Path $candidate | Out-Null
    return (Resolve-Path $candidate).Path
}

function Write-JsonFile([string]$Path, $Value, [int]$Depth = 8) {
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-NativeChecked([string]$Label, [scriptblock]$Command) {
    Write-Host "[$Label]"
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

function Ensure-PythonDependencies {
    $check = & python -c "import PIL, numpy" 2>&1
    if ($LASTEXITCODE -eq 0) { return }
    if ($SkipDependencyInstall) {
        throw "Pillow/numpy are missing and -SkipDependencyInstall was requested. Python output: $check"
    }
    Invoke-NativeChecked 'Install Pillow/numpy' { python -m pip install Pillow numpy }
    Invoke-NativeChecked 'Verify Pillow/numpy' { python -c "import PIL, numpy; print('KROLIK_TARGET_DEPENDENCIES status=ok')" }
}

function Resolve-GodotExecutable {
    if ($GodotPath) {
        $resolved = (Resolve-Path -LiteralPath $GodotPath).Path
        Assert-File $resolved 'Godot executable'
        return $resolved
    }

    New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
    $archive = Join-Path $CacheRoot $GodotArchiveName
    $binDir = Join-Path $CacheRoot 'godot-bin'
    $exe = Join-Path $binDir "Godot_v$GodotVersion-stable_win64.exe"

    $archiveValid = $false
    if (Test-Path -LiteralPath $archive -PathType Leaf) {
        $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        $archiveValid = $actual -eq $GodotArchiveSha256
        if (-not $archiveValid) {
            Write-Warning "Cached Godot archive checksum mismatch; redownloading."
            Remove-Item -LiteralPath $archive -Force
        }
    }
    if (-not $archiveValid) {
        Write-Host "Downloading checksum-pinned Godot $GodotVersion..."
        Invoke-WebRequest -Uri $GodotDownloadUrl -OutFile $archive
        $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $GodotArchiveSha256) {
            throw "Godot archive SHA-256 mismatch: $actual"
        }
    }

    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        if (Test-Path -LiteralPath $binDir) { Remove-Item -LiteralPath $binDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $binDir -Force
    }
    Assert-File $exe 'Pinned Godot executable'
    return (Resolve-Path -LiteralPath $exe).Path
}

function Assert-GodotVersion([string]$Exe) {
    $text = (& $Exe --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $text -notmatch [regex]::Escape($GodotVersion)) {
        throw "Expected Godot $GodotVersion, got: $text"
    }
    return $text
}

function Test-SoftwareRenderer([string]$Renderer) {
    foreach ($pattern in $SoftwareRendererPatterns) {
        if ($Renderer -match [regex]::Escape($pattern)) { return $true }
    }
    return $false
}

function Parse-MetricLine([string]$Line) {
    $values = @{}
    if (-not $Line) { return $values }
    $matches = [regex]::Matches($Line, '(?<key>[A-Za-z0-9_]+)=(?<value>.*?)(?=\s+[A-Za-z0-9_]+=|$)')
    foreach ($match in $matches) {
        $values[$match.Groups['key'].Value] = $match.Groups['value'].Value.Trim()
    }
    return $values
}

function To-Double($Value, [double]$Fallback = 0.0) {
    if ($null -eq $Value) { return $Fallback }
    $parsed = 0.0
    if ([double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }
    return $Fallback
}

function Get-Median($Values) {
    $clean = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ } | Sort-Object)
    if ($clean.Count -eq 0) { return $null }
    $middle = [int][math]::Floor($clean.Count / 2)
    if (($clean.Count % 2) -eq 1) { return [double]$clean[$middle] }
    return ([double]$clean[$middle - 1] + [double]$clean[$middle]) / 2.0
}

function Set-ChildEnvironment([hashtable]$Values) {
    $previous = @{}
    foreach ($key in $Values.Keys) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, [string]$Values[$key], 'Process')
    }
    return $previous
}

function Restore-ChildEnvironment([hashtable]$Previous, [hashtable]$Values) {
    foreach ($key in $Values.Keys) {
        [Environment]::SetEnvironmentVariable($key, $Previous[$key], 'Process')
    }
}

function Invoke-GodotMeasuredRun {
    param(
        [string]$Godot,
        [string]$Mode,
        [int]$AgentCount,
        [int]$Iteration,
        [string]$Artifacts,
        [hashtable]$Environment,
        [string]$Harness,
        [string]$MetricPrefix,
        [string]$RenderPrefix
    )

    $safeMode = $Mode -replace '[^A-Za-z0-9_-]', '_'
    $runName = "${safeMode}_${AgentCount}_r${Iteration}"
    $stdout = Join-Path $Artifacts "$runName.stdout.txt"
    $stderr = Join-Path $Artifacts "$runName.stderr.txt"
    $screenshot = Join-Path $Artifacts "$runName.png"
    $Environment['KROLIK_TARGET_BENCHMARK_SCREENSHOT'] = $screenshot

    if ($Mode -eq 'no_lod') {
        $Environment['KROLIK_STRESS_SCREENSHOT_PATH'] = $screenshot
    } else {
        $Environment['KROLIK_LOD_SCREENSHOT_PATH'] = $screenshot
    }

    $previous = Set-ChildEnvironment $Environment
    $timedOut = $false
    $exitCode = -999
    [long]$peak = 0
    $started = Get-Date
    try {
        $arguments = @(
            '--path', 'runtime_godot',
            '--rendering-method', 'gl_compatibility',
            '--audio-driver', 'Dummy',
            '--script', $Harness
        )
        $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WorkingDirectory $RepoRoot -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $deadline = (Get-Date).AddSeconds(180)
        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 100
            $process.Refresh()
            if ($process.WorkingSet64 -gt $peak) { $peak = $process.WorkingSet64 }
            if ((Get-Date) -gt $deadline) {
                $timedOut = $true
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                break
            }
        }
        $process.WaitForExit()
        if (-not $timedOut) { $exitCode = $process.ExitCode }
    } finally {
        Restore-ChildEnvironment $previous $Environment
    }

    $ended = Get-Date
    $out = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw } else { '' }
    $err = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw } else { '' }
    $metricLine = ($out -split "`r?`n" | Where-Object { $_ -like "$MetricPrefix *" } | Select-Object -Last 1)
    $renderLine = ($out -split "`r?`n" | Where-Object { $_ -like "$RenderPrefix *" } | Select-Object -Last 1)
    $metric = Parse-MetricLine $metricLine
    $renderer = if ($metric.ContainsKey('renderer')) { [string]$metric['renderer'] } else { '' }
    $fps = if ($metric.ContainsKey('sim_fps')) { To-Double $metric['sim_fps'] } else { 0.0 }
    $softwareRenderer = if ($renderer) { Test-SoftwareRenderer $renderer } else { $true }
    $fatalMarker = ($out -match 'SCRIPT ERROR|Parse Error|Failed to load script|KROLIK stress:|KROLIK LOD scale:') -or ($err -match 'SCRIPT ERROR|Parse Error|Failed to load script')
    $ok = (-not $timedOut) -and $exitCode -eq 0 -and [bool]$metricLine -and [bool]$renderLine -and (-not $fatalMarker) -and (Test-Path -LiteralPath $screenshot)

    $record = [pscustomobject]@{
        mode = $Mode
        agents = $AgentCount
        repeat = $Iteration
        status = if ($ok) { 'ok' } else { 'failed' }
        hardware_valid = $ok -and (-not $softwareRenderer)
        software_renderer = $softwareRenderer
        renderer = $renderer
        fps = [math]::Round($fps, 4)
        peak_working_set_bytes = $peak
        peak_working_set_mib = [math]::Round($peak / 1MB, 2)
        exit_code = $exitCode
        timed_out = $timedOut
        fatal_marker = $fatalMarker
        elapsed_seconds = [math]::Round(($ended - $started).TotalSeconds, 3)
        metric = $metricLine
        render_metric = $renderLine
        stdout = [IO.Path]::GetRelativePath($Artifacts, $stdout)
        stderr = [IO.Path]::GetRelativePath($Artifacts, $stderr)
        screenshot = if (Test-Path -LiteralPath $screenshot) { [IO.Path]::GetRelativePath($Artifacts, $screenshot) } else { '' }
    }

    Write-Host ("KROLIK_TARGET_POINT mode={0} agents={1} repeat={2} status={3} hardware_valid={4} fps={5} peak_mib={6} renderer={7}" -f `
        $Mode, $AgentCount, $Iteration, $record.status, $record.hardware_valid, $record.fps, $record.peak_working_set_mib, $renderer)
    return $record
}

function Build-Summary($Runs) {
    $summary = @()
    $groups = $Runs | Group-Object mode, agents
    foreach ($group in $groups) {
        $rows = @($group.Group)
        $successful = @($rows | Where-Object { $_.status -eq 'ok' })
        $first = $rows | Select-Object -First 1
        $medianFps = Get-Median @($successful | ForEach-Object { $_.fps })
        $medianPeak = Get-Median @($successful | ForEach-Object { $_.peak_working_set_mib })
        $baseline = $HostedBaselines | Where-Object { $_.mode -eq $first.mode -and $_.agents -eq $first.agents } | Select-Object -First 1
        $fpsMultiple = $null
        $memoryDelta = $null
        if ($null -ne $medianFps -and $null -ne $baseline) {
            $fpsMultiple = [math]::Round(([double]$medianFps / [double]$baseline.fps), 3)
        }
        if ($null -ne $medianPeak -and $null -ne $baseline) {
            $memoryDelta = [math]::Round(([double]$medianPeak - [double]$baseline.peak_mib), 2)
        }
        $summary += [pscustomobject]@{
            mode = $first.mode
            agents = [int]$first.agents
            successful_runs = $successful.Count
            requested_runs = $rows.Count
            hardware_valid_runs = @($successful | Where-Object { $_.hardware_valid }).Count
            median_fps = if ($null -ne $medianFps) { [math]::Round([double]$medianFps, 3) } else { $null }
            median_peak_mib = if ($null -ne $medianPeak) { [math]::Round([double]$medianPeak, 2) } else { $null }
            renderer = (@($successful.renderer | Where-Object { $_ } | Sort-Object -Unique) -join ' | ')
            hosted_fps = if ($null -ne $baseline) { $baseline.fps } else { $null }
            hosted_peak_mib = if ($null -ne $baseline) { $baseline.peak_mib } else { $null }
            fps_multiple_vs_hosted = $fpsMultiple
            peak_mib_delta_vs_hosted = $memoryDelta
        }
    }
    return @($summary | Sort-Object mode, agents)
}

function Write-MarkdownReport([string]$Path, $System, $Summary, $Runs, [string]$GodotText, [bool]$OverallValid) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# KROLIK target-hardware benchmark')
    $lines.Add('')
    $lines.Add("- Result valid for target-hardware comparison: **$OverallValid**")
    $lines.Add("- Git commit: ``$($System.git_head)``")
    $lines.Add("- Godot: ``$GodotText``")
    $lines.Add("- CPU: $($System.cpu)")
    $lines.Add("- RAM: $($System.total_ram_gib) GiB")
    $gpuNames = @($System.video_controllers | ForEach-Object { $_.name }) -join ' | '
    $lines.Add("- GPU(s): $gpuNames")
    $lines.Add("- OS: $($System.os) $($System.os_version) build $($System.os_build)")
    $lines.Add("- Power plan: $($System.power_plan)")
    $lines.Add('')
    $lines.Add('## Production workload summary')
    $lines.Add('')
    $lines.Add('| Mode | Agents | Valid runs | Median FPS | Median peak MiB | Renderer | Hosted FPS | Hosted peak MiB | FPS multiple |')
    $lines.Add('| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: |')
    foreach ($row in $Summary) {
        $fps = if ($null -eq $row.median_fps) { '-' } else { [string]$row.median_fps }
        $mib = if ($null -eq $row.median_peak_mib) { '-' } else { [string]$row.median_peak_mib }
        $hostedFps = if ($null -eq $row.hosted_fps) { '-' } else { [string]$row.hosted_fps }
        $hostedMib = if ($null -eq $row.hosted_peak_mib) { '-' } else { [string]$row.hosted_peak_mib }
        $multiple = if ($null -eq $row.fps_multiple_vs_hosted) { '-' } else { [string]$row.fps_multiple_vs_hosted + 'x' }
        $lines.Add("| $($row.mode) | $($row.agents) | $($row.hardware_valid_runs)/$($row.requested_runs) | $fps | $mib | $($row.renderer) | $hostedFps | $hostedMib | $multiple |")
    }
    $lines.Add('')
    $lines.Add('Hosted references use GitHub-hosted Windows with ANGLE / Microsoft Basic Render Driver. They are intentionally kept only as a stable software-render regression reference; they are not expected target-GPU performance.')
    $lines.Add('')
    $lines.Add('## Raw run status')
    $lines.Add('')
    foreach ($run in $Runs) {
        $lines.Add("- ``$($run.mode)`` $($run.agents) agents r$($run.repeat): status=$($run.status), hardware_valid=$($run.hardware_valid), fps=$($run.fps), peak=$($run.peak_working_set_mib) MiB, renderer=``$($run.renderer)``")
    }
    $lines.Add('')
    $lines.Add('A run is marked hardware-valid only when the production harness completes successfully, writes render evidence, and Godot reports a non-software video adapter. Raw stdout/stderr and screenshots are retained beside this report.')
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

# Contract validation is deliberately cheap so CI can validate the collector without
# pretending a GitHub-hosted software renderer is the user's target GPU.
$Agents = @($Agents | Sort-Object -Unique)
if ($Agents.Count -eq 0) { throw 'At least one agent count is required.' }
foreach ($agentCount in $Agents) {
    if ($agentCount -lt 1 -or $agentCount -gt 1000) { throw "Agent count out of supported range: $agentCount" }
}

Assert-File (Join-Path $RepoRoot 'tools/build_core_vertical_slice.py') 'Core vertical-slice builder'
Assert-File (Join-Path $RuntimeRoot 'scripts/stress_harness.gd') 'No-LOD stress harness'
Assert-File (Join-Path $RuntimeRoot 'scripts/lod_scale_harness.gd') 'LOD stress harness'
Assert-File (Join-Path $RuntimeRoot 'project.godot') 'Godot project'

$ArtifactsRoot = Get-OutputRoot
$validation = [pscustomobject]@{
    schema = 'krolik.target-hardware-benchmark-contract/1'
    godot_version = $GodotVersion
    godot_archive_sha256 = $GodotArchiveSha256
    rendering_method = 'gl_compatibility'
    no_lod_agents = $Agents
    repeat = $Repeat
    lod_enabled = (-not $SkipLod)
    lod_agents = 500
    warmup_frames = 30
    sample_frames = 120
    watchdog_seconds = 180
    production_manifest = $ManifestResPath
    stress_harness = 'res://scripts/stress_harness.gd'
    lod_harness = 'res://scripts/lod_scale_harness.gd'
    software_renderer_patterns = $SoftwareRendererPatterns
    hosted_baselines = $HostedBaselines
}
Write-JsonFile (Join-Path $ArtifactsRoot 'validation.json') $validation
Write-Host "KROLIK_TARGET_BENCHMARK_CONTRACT status=ok output=$ArtifactsRoot agents=$($Agents -join ',') repeat=$Repeat lod=$(-not $SkipLod)"
if ($ValidateOnly) { exit 0 }

if ($env:OS -ne 'Windows_NT') {
    throw 'Target-hardware benchmark collector currently supports native Windows only.'
}

$system = Get-SystemSnapshot
Write-JsonFile (Join-Path $ArtifactsRoot 'system.json') $system
Write-Section 'Environment'
Write-Host "Git: $($system.git_head)"
Write-Host "CPU: $($system.cpu)"
Write-Host "RAM: $($system.total_ram_gib) GiB"
foreach ($gpu in $system.video_controllers) {
    Write-Host "GPU: $($gpu.name) driver=$($gpu.driver_version)"
}

$godot = $null
$godotVersionText = ''
$runs = New-Object System.Collections.Generic.List[object]
$finalFailure = $null

try {
    Ensure-PythonDependencies
    $godot = Resolve-GodotExecutable
    $godotVersionText = Assert-GodotVersion $godot
    Write-Host "Godot: $godotVersionText"

    Write-Section 'Build production package'
    if (Test-Path -LiteralPath $GeneratedPackageRoot) { Remove-Item -LiteralPath $GeneratedPackageRoot -Recurse -Force }
    $previousPythonPath = [Environment]::GetEnvironmentVariable('PYTHONPATH', 'Process')
    $pathSeparator = [IO.Path]::PathSeparator
    $benchmarkPythonPath = if ([string]::IsNullOrWhiteSpace($previousPythonPath)) { $RepoRoot } else { "$RepoRoot$pathSeparator$previousPythonPath" }
    [Environment]::SetEnvironmentVariable('PYTHONPATH', $benchmarkPythonPath, 'Process')
    try {
        Invoke-NativeChecked 'Build core vertical slice' { python (Join-Path $RepoRoot 'tools/build_core_vertical_slice.py') --output-root $GeneratedPackageRoot }
    } finally {
        [Environment]::SetEnvironmentVariable('PYTHONPATH', $previousPythonPath, 'Process')
    }
    Assert-File $ManifestDiskPath 'Generated production manifest'

    Write-Section 'Import Godot project'
    $importStdout = Join-Path $ArtifactsRoot 'godot_import.stdout.txt'
    $importStderr = Join-Path $ArtifactsRoot 'godot_import.stderr.txt'
    $importProcess = Start-Process -FilePath $godot -ArgumentList @('--headless','--path','runtime_godot','--editor','--quit') -WorkingDirectory $RepoRoot -PassThru -Wait -RedirectStandardOutput $importStdout -RedirectStandardError $importStderr
    $importOut = if (Test-Path $importStdout) { Get-Content $importStdout -Raw } else { '' }
    $importErr = if (Test-Path $importStderr) { Get-Content $importStderr -Raw } else { '' }
    if ($importProcess.ExitCode -ne 0 -or $importOut -match 'SCRIPT ERROR|Parse Error|Failed to load script|Cannot get class|Could not resolve class' -or $importErr -match 'SCRIPT ERROR|Parse Error|Failed to load script') {
        throw "Godot project import failed. See $importStdout / $importStderr"
    }

    foreach ($agentCount in $Agents) {
        for ($iteration = 1; $iteration -le $Repeat; $iteration++) {
            Write-Section "No-LOD $agentCount agents, repeat $iteration/$Repeat"
            $envMap = @{
                KROLIK_STRESS_AGENTS = [string]$agentCount
                KROLIK_STRESS_WARMUP_FRAMES = '30'
                KROLIK_STRESS_SAMPLE_FRAMES = '120'
                KROLIK_STRESS_MAX_SECONDS = '60'
                KROLIK_STRESS_MIN_MOVED_SHARE = '0.80'
                KROLIK_STRESS_MIN_TRAVEL_PX = '8'
                KROLIK_STRESS_MIN_PHASE_SECONDS = '2.0'
                KROLIK_STRESS_MANIFEST_PATH = $ManifestResPath
                KROLIK_STRESS_REQUIRE_VISUALS = '1'
            }
            $record = Invoke-GodotMeasuredRun -Godot $godot -Mode 'no_lod' -AgentCount $agentCount -Iteration $iteration -Artifacts $ArtifactsRoot -Environment $envMap -Harness 'res://scripts/stress_harness.gd' -MetricPrefix 'KROLIK_STRESS_METRIC' -RenderPrefix 'KROLIK_RENDER_STRESS'
            $runs.Add($record)
        }
    }

    if (-not $SkipLod) {
        for ($iteration = 1; $iteration -le $Repeat; $iteration++) {
            Write-Section "LOD 500 agents, repeat $iteration/$Repeat"
            $envMap = @{
                KROLIK_LOD_AGENTS = '500'
                KROLIK_LOD_WARMUP_FRAMES = '30'
                KROLIK_LOD_SAMPLE_FRAMES = '120'
                KROLIK_LOD_MAX_SECONDS = '60'
                KROLIK_LOD_FULL_RADIUS = '180'
                KROLIK_LOD_SLEEP_RADIUS = '360'
                KROLIK_LOD_WAKE_RADIUS = '330'
                KROLIK_LOD_MANIFEST_PATH = $ManifestResPath
            }
            $record = Invoke-GodotMeasuredRun -Godot $godot -Mode 'lod' -AgentCount 500 -Iteration $iteration -Artifacts $ArtifactsRoot -Environment $envMap -Harness 'res://scripts/lod_scale_harness.gd' -MetricPrefix 'KROLIK_LOD_SCALE_METRIC' -RenderPrefix 'KROLIK_LOD_RENDER_STRESS'
            $runs.Add($record)
        }
    }
} catch {
    $finalFailure = $_
} finally {
    if (Test-Path -LiteralPath $GeneratedPackageRoot) {
        Remove-Item -LiteralPath $GeneratedPackageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$runArray = @($runs | ForEach-Object { $_ })
Write-JsonFile (Join-Path $ArtifactsRoot 'runs.json') $runArray 8
$summary = Build-Summary $runArray
Write-JsonFile (Join-Path $ArtifactsRoot 'summary.json') $summary 8
$summary | Export-Csv -LiteralPath (Join-Path $ArtifactsRoot 'summary.csv') -NoTypeInformation -Encoding UTF8

$expectedPoints = $Agents.Count + $(if ($SkipLod) { 0 } else { 1 })
$expectedRuns = $expectedPoints * $Repeat
$successfulRuns = @($runArray | Where-Object { $_.status -eq 'ok' }).Count
$hardwareValidRuns = @($runArray | Where-Object { $_.hardware_valid }).Count
$overallValid = ($null -eq $finalFailure) -and $runArray.Count -eq $expectedRuns -and $successfulRuns -eq $expectedRuns -and $hardwareValidRuns -eq $expectedRuns

$result = [pscustomobject]@{
    schema = 'krolik.target-hardware-benchmark-result/1'
    valid = $overallValid
    expected_runs = $expectedRuns
    completed_runs = $runArray.Count
    successful_runs = $successfulRuns
    hardware_valid_runs = $hardwareValidRuns
    output_root = $ArtifactsRoot
    git_head = $system.git_head
    godot = $godotVersionText
    summary = $summary
    failure = if ($null -ne $finalFailure) { [string]$finalFailure } else { '' }
}
Write-JsonFile (Join-Path $ArtifactsRoot 'result.json') $result 10
Write-MarkdownReport (Join-Path $ArtifactsRoot 'REPORT.md') $system $summary $runArray $godotVersionText $overallValid

Write-Section 'Result'
Write-Host "KROLIK_TARGET_BENCHMARK_RESULT valid=$overallValid completed=$($runArray.Count)/$expectedRuns hardware_valid=$hardwareValidRuns/$expectedRuns output=$ArtifactsRoot"
foreach ($row in $summary) {
    Write-Host ("KROLIK_TARGET_SUMMARY mode={0} agents={1} median_fps={2} median_peak_mib={3} renderer={4} vs_hosted={5}x" -f `
        $row.mode, $row.agents, $row.median_fps, $row.median_peak_mib, $row.renderer, $row.fps_multiple_vs_hosted)
}

if ($null -ne $finalFailure) {
    [Console]::Error.WriteLine("Benchmark aborted: $finalFailure")
    exit 1
}
if (-not $overallValid) {
    [Console]::Error.WriteLine("Benchmark completed but is not a valid target-hardware result. Inspect REPORT.md, runs.json, stdout/stderr and renderer fields in: $ArtifactsRoot")
    exit 2
}
exit 0
