#!/usr/bin/env python3
"""Local Windows preview export. Does not bypass or change the public Steam release gate."""
import argparse,hashlib,json,re,shutil,subprocess,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
TEMPLATE_SHA='d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562'
def main():
 p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--template',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 template=a.template.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
 version=json.loads((ROOT/'config/product.json').read_text())['version'].split('-')[0]
 template_sha=hashlib.sha256(template.read_bytes()).hexdigest()
 if template_sha not in [TEMPLATE_SHA,'7a04fc118a389321d784af36ca24a3a9b99494a0aa2f6ad42c75a1fd4dc1adb8','9ddc4873118000f30e4c237607355847db4c2a15f25ec45d6c0f07547c818fee','85331073ec1e95bf0f09dc9535c03887627f5bfd5b9484ba1bef58a5d696ecbd']:raise SystemExit('Wrong export template hash')
 preset=ROOT/'export_presets.cfg';original=preset.read_text()
 try:
  preset.write_text(original.replace('custom_template/release=""','custom_template/release="'+template.as_posix()+'"'))
  result=subprocess.run([str(Path(a.godot).resolve()),'--headless','--path',str(ROOT),'--export-release','Windows Desktop',str(out/'Companion.exe')],capture_output=True,text=True,timeout=180)
 finally:preset.write_text(original)
 log=re.sub(r"\x1b\[[0-9;]*m", "", result.stdout+result.stderr);(ROOT/'reports/windows_export.txt').write_text(log)
 if result.returncode or 'SCRIPT ERROR:' in log or '\nERROR:' in log:print(log);raise SystemExit('Windows preview export failed')
 # Validate the exported resource pack with the Linux engine, without project files.
 smoke=subprocess.run([str(Path(a.godot).resolve()),'--headless','--main-pack',str(out/'Companion.pck' if (out/'Companion.pck').exists() else out/'Companion.exe'),'--','--ui-smoke','--test-mode'],cwd=out,env=dict(__import__('os').environ,XDG_DATA_HOME=str(out/'.test-user'),XDG_CONFIG_HOME=str(out/'.test-user')),capture_output=True,text=True,timeout=90)
 smoke_log=smoke.stdout+smoke.stderr;(ROOT/'reports/exported_pack.txt').write_text(smoke_log)
 if smoke.returncode or 'SCRIPT ERROR:' in smoke_log or '\nERROR:' in smoke_log or 'UI_SMOKE_OK' not in smoke_log:print(smoke_log);raise SystemExit('Exported resource-pack smoke failed')
 shutil.rmtree(out/'.test-user',ignore_errors=True)
 exe=out/'Companion.exe' 
 if not exe.exists() or exe.read_bytes()[:2]!=b'MZ':raise SystemExit('Missing PE executable')
 shutil.copytree(ROOT/'legal',out/'legal',dirs_exist_ok=True)
 (out/'START_HERE.txt').write_text('''LEEMON COMPANION PREVIEW 0.6.0 — WINDOWS x64\n\n1. Unzip the entire folder. Run Companion.exe. No Godot or Python installation required.\n2. The full-body desktop character is the main window. Click: chat. Right click: quick menu. Drag to move.
   Restore from the taskbar, or click the companion in the Windows notification area to recover it.
   Right-click its taskbar icon and Close window to exit. Missing art opens a visible recovery panel.\n3. Click the character to open chat. Installed AI wakes on the first message.
   If AI is not installed, use the Install AI button right inside chat.\n   First setup downloads about 1.86 GB from official sources and needs about 2.5 GB free disk space.\n   After setup, chat/translation works locally. No cloud API key.\n4. The active character is now the Leemon lemon mascot, with one graphite/amber style.
   Six articulated cutout parts share one source texture. Eleven procedural motion states:
   idle, hello, thinking, talking, success, hesitation, grab, walking, listening, stretch and settling.
   These are authored cutout motions, not finished hand-drawn animation clips or a 3D model.
   Natural commands: "open notepad", "открой проводник", "打开记事本".
   Launches a matching installed Start Menu app or known folder. Only the executable is launched,
   never generated code. Ambiguous names ask for clarification. "Started" does not confirm a window.
   New commands: "time in Beijing", "время в Москве", "北京几点" work offline.
   The IANA 2026e/CLDR directory covers 597 zones, not every city in the world.
   "remind me in 5 minutes check download" / "напомни через 5 минут проверить загрузку".
   Reminders persist; when the app is closed, overdue reminders appear at next startup.
   "translate clipboard to Russian" / "переведи буфер на английский" uses only the
   owned local worker, reads only after explicit command, and does not save the source.
   Notes, timers, reminders, clocks and browser handoff work without the model.
   Settings: opt-in chat saving (100 messages / 256 KiB), Delete history, per-note Delete.
   Usage page: process RAM and sampled CPU for the app and its owned AI worker.
   Unzip this complete package into an EMPTY folder; run Companion.exe.
   Your existing model and profile stay in AppData. No BAT/CMD patches needed.\n5. Close the app to stop its worker; Stop AI frees model memory; pause stops AI and effects.\n\nThis is a private test build, not the final Steam release. Detailed facial animation, ASR, finished frame clips,\nvisual screen understanding and browser page reading are NOT ready. Movement uses an articulated 2D cutout with authored curves. System voices depend on your Windows installation.\nWindows execution, transparency, speech and capture still need a real user test.\nIf local AI cannot start, install the official Microsoft Visual C++ x64 runtime:\nhttps://aka.ms/vs/17/release/vc_redist.x64.exe\nThis system dependency is not automatically installed in this preview.\nProject source and checkpoint: https://github.com/LeemonSun/KROLIK-Collection-Vault\n\nDownloaded AI data: %APPDATA%/Godot/app_userdata/Companion Foundation/local-ai-v1\nLicenses are included under legal/. Character concept art was AI-generated; no exclusive\ncopyright claim or commercial asset clearance is implied.\n''',encoding='utf-8')
 metadata={'version':version,'target':'windows-x86_64','exe_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'exe_bytes':exe.stat().st_size,'template_sha256':template_sha,'active_character':'leemon_01','motion_type':'articulated_2d_authored_procedural','motion_states':11,'public_release_ready':False,'windows_executed_here':False}
 (out/'BUILD_INFO.json').write_text(json.dumps(metadata,indent=2)+'\n')
 archive=out.parent/('Companion_Preview_Windows_v'+version+'.zip')
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for file in [out/'Companion.exe',out/'Companion.pck',out/'START_HERE.txt',out/'BUILD_INFO.json',*sorted((out/'legal').rglob('*'))]:
   if file.is_file():z.write(file,'Companion_Preview/'+file.relative_to(out).as_posix())
 digest=hashlib.sha256(archive.read_bytes()).hexdigest();archive.with_suffix('.zip.sha256').write_text(digest+'  '+archive.name+'\n')
 print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'sha256':digest,'exe_bytes':exe.stat().st_size}))
if __name__=='__main__':main()
