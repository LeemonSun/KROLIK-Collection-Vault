# KROLIK target-hardware benchmark

This procedure measures the **same production Godot workloads** used by the hosted Windows regressions on a real Windows gaming PC. It is intended to replace guesses about target-machine performance with a traceable local result.

The collector does **not** publish or upload local results automatically. Everything is written to a local timestamped folder under `target_benchmark_artifacts/` unless another output path is supplied.

## What it measures

The default run performs three repeats of each workload and reports the median:

| Workload | Agents | Production path |
| --- | ---: | --- |
| no LOD | 220 | full `VaultCharacterAgent`, GPU skin, AI, personality, memory, facial state, locomotion |
| no LOD | 300 | same path |
| no LOD | 500 | same path |
| LOD | 500 | production full/reduced/sleep population LOD with resource residency |

Each point uses the same benchmark settings as the corresponding GitHub-hosted Windows workflow:

- Godot `4.7.2`;
- `gl_compatibility` rendering method;
- 30 warm-up physics frames;
- 120 measured physics frames;
- production core runtime package;
- render-evidence screenshot;
- process working-set sampling every 100 ms;
- 180-second external watchdog.

The script also records the current Git commit, Windows version/build, CPU, RAM, GPU/video controllers, GPU driver versions, active Windows power plan, Python version, Godot version, raw Godot output, screenshots and renderer identity.

## One-command run

Open PowerShell in the repository root and run:

```powershell
pwsh -ExecutionPolicy Bypass -File tools/run_target_hardware_benchmark.ps1
```

The default is `Repeat=3`. That gives a useful median without changing the actual workload. For a quick diagnostic pass:

```powershell
pwsh -ExecutionPolicy Bypass -File tools/run_target_hardware_benchmark.ps1 -Repeat 1
```

To write results to a specific folder:

```powershell
pwsh -ExecutionPolicy Bypass -File tools/run_target_hardware_benchmark.ps1 -OutputRoot C:\KROLIK-benchmark
```

To use an already installed Godot executable instead of the script-managed copy:

```powershell
pwsh -ExecutionPolicy Bypass -File tools/run_target_hardware_benchmark.ps1 -GodotPath C:\Tools\Godot_v4.7.2-stable_win64.exe
```

The supplied executable must report Godot `4.7.2`. Using the automatically managed copy is preferred because the script downloads the official Windows archive and verifies SHA-256:

`731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953`

## Local prerequisites

Required:

- Windows;
- Python available as `python`;
- Git is recommended so the result can contain the exact commit SHA;
- internet access for the first automatic Godot download and, if needed, Python `Pillow`/`numpy` installation.

You do **not** need to install Godot manually. The collector caches the checksum-pinned Godot archive/executable under `.target_benchmark/`.

For the cleanest performance number:

- update to the intended AMD/NVIDIA/Intel graphics driver first;
- use AC power and the normal performance-oriented Windows power mode you actually plan to use;
- close games, video encoders, GPU stress tools and heavy background jobs;
- leave ordinary desktop services running — this is a product-machine measurement, not an artificial stripped benchmark OS;
- do not force a different Godot rendering backend for the comparison run. `gl_compatibility` is intentional because it matches the hosted baseline workload.

## Renderer validity gate

A successful benchmark is not automatically a valid target-GPU benchmark.

The collector reads `RenderingServer.get_video_adapter_name()` from the production harness and marks every run with `hardware_valid`.

The result is rejected as a target-hardware measurement if the reported adapter looks like a software renderer, including:

- `Microsoft Basic Render Driver`;
- `llvmpipe`;
- `SwiftShader`;
- another adapter explicitly identifying itself as a software renderer.

The raw files are still retained when this happens, so the failure can be diagnosed without rerunning blindly. A normal target-machine result should name the real GPU/driver path rather than the hosted Microsoft Basic Render Driver baseline.

## Output

A completed output folder contains at least:

- `REPORT.md` — human-readable result and comparison table;
- `result.json` — overall validity/result object;
- `summary.json` — aggregated per-workload medians;
- `summary.csv` — spreadsheet-friendly summary;
- `runs.json` — every individual repeat;
- `system.json` — machine/OS/CPU/RAM/GPU/driver/power-plan snapshot;
- `validation.json` — immutable benchmark contract for that invocation;
- `godot_import.stdout.txt` / `.stderr.txt`;
- one stdout/stderr pair per measured run;
- one rendered screenshot per successful measured run.

If the script exits with code `2`, it completed enough work to write evidence but at least one run is not a valid target-hardware result (for example a software renderer). Exit code `1` means setup/import/benchmark execution itself aborted.

## Hosted reference values

The report embeds the existing hosted-Windows software-render references so a local result is immediately comparable:

| Mode | Agents | Hosted FPS | Hosted peak working set |
| --- | ---: | ---: | ---: |
| no LOD | 220 | 6.96 | 603.45 MiB |
| no LOD | 300 | 6.12 | 775.41 MiB |
| no LOD | 500 | 3.42 | 1172.12 MiB |
| LOD | 500 | 11.98 | 1105.21 MiB |

The no-LOD reference is workflow run `34933824299`; the LOD reference is run `34935517813`. Both used GitHub-hosted Windows and Microsoft Basic Render Driver via ANGLE. They are stable regression references, **not** expected real-GPU FPS.

The local report therefore shows both the absolute median and the local/hosted FPS multiple, but it must not be interpreted as a cross-machine GPU benchmark score. Its primary purpose is to answer whether the actual target PC has comfortable headroom for the KROLIK production runtime.

## Contract-only validation

CI uses a cheap mode that validates the PowerShell collector and its pinned settings without pretending the GitHub-hosted software renderer is target hardware:

```powershell
pwsh -File tools/run_target_hardware_benchmark.ps1 -ValidateOnly -OutputRoot target_benchmark_contract
```

This writes `validation.json` and exits before dependency installation, Godot download or rendering. It is safe for repository CI and keeps the real hardware result explicitly local.

## Optional controls

Examples:

```powershell
# Only the three no-LOD production points
pwsh -File tools/run_target_hardware_benchmark.ps1 -SkipLod

# Custom no-LOD population list while preserving the same harness
pwsh -File tools/run_target_hardware_benchmark.ps1 -Agents 220,300,500 -Repeat 3

# Do not auto-install Pillow/numpy; fail if they are absent
pwsh -File tools/run_target_hardware_benchmark.ps1 -SkipDependencyInstall
```

Custom agent counts are exploratory. The canonical apples-to-apples target run remains `220, 300, 500` plus the 500-agent LOD point.

## What a completed local run closes

A valid result closes the current gap between hosted software-render evidence and the actual target machine. It can then be recorded in `docs/AUTONOMOUS_STATE.md` with:

- exact Git SHA;
- GPU/driver identity;
- median 220/300/500 no-LOD FPS and working set;
- median 500-agent LOD FPS and working set;
- production LOD tier distribution from raw metrics;
- screenshots/raw logs as local evidence.

Until that local run exists, KROLIK should continue describing RX-class performance as **unmeasured target hardware**, even though the runtime and collector are production-verified in CI.


## CI contract and orchestration smoke

The Windows benchmark workflow uses two deliberately different checks. The contract job is the cheap syntax/configuration check and does not render. The orchestration smoke executes the real collector end-to-end with a 5-agent production stress point on GitHub-hosted Windows, verifies FPS/screenshot/log evidence, and requires the collector to reject GitHub's software renderer as target-hardware evidence with exit code 2. This proves the orchestration and rejection path without pretending hosted software rendering represents the target PC.
