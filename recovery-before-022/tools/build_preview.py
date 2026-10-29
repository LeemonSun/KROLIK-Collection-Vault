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
 if template_sha not in [TEMPLATE_SHA,'ded4e39d97ea7a4f21f49fc21f8cfb6b545b0f433dad6f297963daa9a91f9663','344e14c03b038a9193b0e327ef7e2d061953b4615d5d1631aaa89aabb8566652','0fe6bf849f3daa0353f18ba45a9e3790657cf4e307143cd0011c19a528f7502c','3959cd3452534bcf79b59fe568334abe0749a45482272eb5036dd83750158b52','55166cfe1374c1e8bd24741f56e5116d40b0ba8a72f0c27926431ba886fbb08c','49bdb7a55e668a3a5e8f88f374ac502b84454d23bde9561bf3b9d8e38bab2538','548c75741efc597e4e54037d85838d37f43bbfffbffc750f29ee49289a74793b','33c4fcdb4bf6d9c4452d881a9d57467125630719cbd5e7d231ffb7d16a6b9b1e','7a04fc118a389321d784af36ca24a3a9b99494a0aa2f6ad42c75a1fd4dc1adb8','9ddc4873118000f30e4c237607355847db4c2a15f25ec45d6c0f07547c818fee','85331073ec1e95bf0f09dc9535c03887627f5bfd5b9484ba1bef58a5d696ecbd','83813377ae61e5cb02cec687a38da5ab83749964a59fefaabd20b3d40f5167e6']:raise SystemExit('Wrong export template hash')
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
 (out/'START_HERE.txt').write_text((ROOT/'docs/PREVIEW_README.txt').read_text(encoding='utf-8').replace('{VERSION}',version),encoding='utf-8')
 metadata={'version':version,'target':'windows-x86_64','exe_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'exe_bytes':exe.stat().st_size,'template_sha256':template_sha,'active_character':'leemon_01','motion_type':'articulated_2d_authored_procedural','motion_states':26,'local_voice':True,'explicit_screen_vision':True,'scoped_windows_uia':True,'one_step_goal_proposals':True,'bounded_user_workflows':True,'bounded_adaptive_uia_loop':True,'whole_retained_chat_copy':True,'reviewed_generated_field_drafts':True,'compact_bound_action_choices':True,'scoped_control_context':True,'bounded_read_only_verification':True,'uia_context_ephemeral':True,'distance_driven_locomotion':True,'task_pose_arbitration':True,'hidden_rig_suspension':True,'following_speech_bubbles':True,'plain_authoring_pipeline':True,'bounded_grounding_repair':True,'registry_capability_answers':True,'inference_stage_metrics':True,'production_default_model_changed':False,'bounded_chat_queue':True,'bounded_office_adapters':True,'local_calculator':True,'unit_conversion':True,'windows_settings_handoff':True,'explicit_public_page_reader':True,'live_public_network_verified_here':False,'economy_compute_mode':True,'typed_xlsx_cells':True,'docx_adjacent_runs':True,'bounded_range_summary':True,'reviewed_text_patches':True,'compact_facts':True,'steam_cloud_connected':False,'available_ram_guard':True,'speech_bubbles':True,'explicit_window_reading':True,'optional_offline_bundle':True,'public_release_ready':False,'windows_executed_here':False}
 (out/'BUILD_INFO.json').write_text(json.dumps(metadata,indent=2)+'\n')
 archive=out.parent/('Companion_Preview_Windows_v'+version+'.zip')
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for file in [out/'Companion.exe',out/'Companion.pck',out/'START_HERE.txt',out/'BUILD_INFO.json',*sorted((out/'legal').rglob('*'))]:
   if file.is_file():z.write(file,'Companion_Preview/'+file.relative_to(out).as_posix())
 digest=hashlib.sha256(archive.read_bytes()).hexdigest();archive.with_suffix('.zip.sha256').write_text(digest+'  '+archive.name+'\n')
 print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'sha256':digest,'exe_bytes':exe.stat().st_size}))
if __name__=='__main__':main()
