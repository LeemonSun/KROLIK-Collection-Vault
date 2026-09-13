from __future__ import annotations

"""Portable runtime-character package builder for KROLIK Collection Vault."""

from hashlib import sha256
from pathlib import Path
from typing import Any
import json
import shutil

RADIUS_BY_BONE = {
    ("head", "neck"): 0.055, ("neck", "pelvis"): 0.095,
    ("neck", "left_shoulder"): 0.055, ("left_shoulder", "left_elbow"): 0.045, ("left_elbow", "left_wrist"): 0.038,
    ("neck", "right_shoulder"): 0.055, ("right_shoulder", "right_elbow"): 0.045, ("right_elbow", "right_wrist"): 0.038,
    ("pelvis", "left_hip"): 0.070, ("left_hip", "left_knee"): 0.060, ("left_knee", "left_ankle"): 0.050,
    ("pelvis", "right_hip"): 0.070, ("right_hip", "right_knee"): 0.060, ("right_knee", "right_ankle"): 0.050,
}

DEFAULT_ANIMATION_GRAPH = {
    "idle": {"clip": "idle_breathe", "loop": True, "blend": 0.18},
    "wander": {"clip": "walk", "loop": True, "blend": 0.12},
    "inspect": {"clip": "inspect", "loop": True, "blend": 0.16},
    "social": {"clip": "social_idle", "loop": True, "blend": 0.16},
    "return_home": {"clip": "walk", "loop": True, "blend": 0.12},
    "contained": {"clip": "contained_idle", "loop": True, "blend": 0.16},
    "rest": {"clip": "rest", "loop": True, "blend": 0.24},
    "disabled": {"clip": "idle_static", "loop": True, "blend": 0.0},
}

SECONDARY_CHANNELS = {
    "hair": {"stiffness": 0.34, "damping": 0.74, "gravity": 0.18, "max_angle": 18.0},
    "chest": {"stiffness": 0.56, "damping": 0.84, "gravity": 0.04, "max_offset": 0.012},
    "hips": {"stiffness": 0.48, "damping": 0.81, "gravity": 0.06, "max_offset": 0.015},
    "accessories": {"stiffness": 0.28, "damping": 0.68, "gravity": 0.24, "max_angle": 24.0},
}

def _json(value: Any, default: Any) -> Any:
    if isinstance(value, (dict, list)): return value
    try: return json.loads(value or "")
    except Exception: return default

def _point(joints: dict[str, Any], name: str) -> dict[str, float] | None:
    p = joints.get(name)
    if not isinstance(p, dict): return None
    try: return {"x": float(p["x"]), "y": float(p["y"])}
    except Exception: return None

def collision_proxies(joints: dict[str, Any], bones: list[list[str]]) -> list[dict[str, Any]]:
    out=[]
    for a,b in bones:
        pa,pb=_point(joints,a),_point(joints,b)
        if not pa or not pb: continue
        radius=RADIUS_BY_BONE.get((a,b),RADIUS_BY_BONE.get((b,a),0.045))
        out.append({"type":"capsule_segment","a":a,"b":b,"p0":pa,"p1":pb,"radius":radius,"sensor":False})
    return out

def rig_health(joints: dict[str, Any], bones: list[list[str]]) -> dict[str, Any]:
    expected={name for bone in bones for name in bone}; present={name for name in expected if _point(joints,name)}
    missing=sorted(expected-present); coverage=len(present)/max(1,len(expected)); impossible=[]
    for name in present:
        p=_point(joints,name)
        if p and not (0.0<=p["x"]<=1.0 and 0.0<=p["y"]<=1.0): impossible.append(name)
    score=max(0.0,min(100.0,coverage*100.0-len(impossible)*15.0))
    return {"score":round(score,2),"coverage":round(coverage,4),"missing":missing,"invalid":impossible}

def build_manifest(*, character: dict[str,Any], image_version: dict[str,Any], rig: dict[str,Any]|None, mind: dict[str,Any]|None, cell_id: str|None=None)->dict[str,Any]:
    rest=_json((rig or {}).get("rest_json"),{}); settings=_json((rig or {}).get("settings_json"),{})
    joints=rest.get("joints",{}) if isinstance(rest,dict) else {}; bones=settings.get("bones",[]) if isinstance(settings,dict) else []
    if not bones:
        try:
            from rig_tools import DEFAULT_BONES
            bones=DEFAULT_BONES
        except Exception: bones=[]
    profile=_json((mind or {}).get("profile_json"),{}); needs=_json((mind or {}).get("needs_json"),{}); runtime=_json((mind or {}).get("runtime_json"),{})
    health=rig_health(joints,bones)
    return {
        "schema":"krolik.runtime-character/1",
        "character":{"id":str(character.get("id") or ""),"name":str(character.get("name") or ""),"status":str(character.get("status") or ""),"home_cell":(mind or {}).get("home_cell_id") or cell_id},
        "visual":{"file":"character.png","width":int(image_version.get("width") or 0),"height":int(image_version.get("height") or 0),"version_id":int(image_version.get("id") or 0),"kind":str(image_version.get("kind") or ""),"pivot":{"x":0.5,"y":0.94},"render_mode":"deformable_2d"},
        "rig":{"id":int((rig or {}).get("id") or 0),"backend":settings.get("backend","none"),"joints":joints,"bones":bones,"mesh":{"cols":int(settings.get("mesh_cols",14)),"rows":int(settings.get("mesh_rows",26)),"influence_radius":float(settings.get("influence_radius",0.17)),"preserve_volume":float(settings.get("preserve_volume",0.62))},"health":health},
        "physics":{"collision":collision_proxies(joints,bones),"secondary":SECONDARY_CHANNELS,"floor_contact_joints":["left_ankle","right_ankle"]},
        "animation":{"state_graph":DEFAULT_ANIMATION_GRAPH,"procedural_blink":{"enabled":True,"min_interval":2.1,"max_interval":6.4,"duration":0.12},"look_at":{"enabled":True,"max_head_deg":16.0,"max_eye":0.06},"breathing":{"enabled":True,"rate":1.0,"amplitude":0.006}},
        "mind":{"enabled":bool((mind or {}).get("enabled",0)),"state":str((mind or {}).get("state") or "idle"),"profile":profile,"needs":needs,"runtime":runtime},
        "interaction":{"joint_targets":["left_wrist","right_wrist","left_ankle","right_ankle","neck","pelvis"],"ik_chains":{"left_wrist":["left_shoulder","left_elbow","left_wrist"],"right_wrist":["right_shoulder","right_elbow","right_wrist"],"left_ankle":["left_hip","left_knee","left_ankle"],"right_ankle":["right_hip","right_knee","right_ankle"]},"supports_constraints":True,"supports_props":True,"solver":"two_bone_ik_v1"},
        "quality":{"runtime_ready":health["score"]>=80.0 and bool(joints),"rig_score":health["score"],"warnings":(["rig_missing_or_low_coverage"] if health["score"]<80.0 else [])},
    }

def write_package(project_root: str|Path, character_id: str, source_image: str|Path, manifest: dict[str,Any])->dict[str,Any]:
    root=Path(project_root); safe="".join(ch if (ch.isalnum() or ch in "-_.") else "_" for ch in character_id).strip("._") or "character"
    out=root/"exports"/"runtime"/safe; out.mkdir(parents=True,exist_ok=True); image_out=out/"character.png"; source=Path(source_image)
    try:
        from PIL import Image
        with Image.open(source) as im: im.convert("RGBA").save(image_out,"PNG",optimize=True)
    except Exception: shutil.copy2(source,image_out)
    manifest=dict(manifest); manifest.setdefault("visual",{})["sha256"]=sha256(image_out.read_bytes()).hexdigest()
    manifest_path=out/"manifest.json"; manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    return {"folder":str(out),"image":str(image_out),"manifest":str(manifest_path),"runtime_ready":bool(manifest.get("quality",{}).get("runtime_ready")),"rig_score":float(manifest.get("quality",{}).get("rig_score",0.0))}
