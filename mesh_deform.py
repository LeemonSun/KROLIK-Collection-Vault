from __future__ import annotations

"""Non-destructive image deformation driven by KROLIK normalized rig joints.

The first implementation deliberately uses a thin-plate-spline (TPS) inverse
warp. It is deterministic, does not invent pixels, and works on any RGBA image.
It bridges the editable skeleton/IK layer and the future GPU weighted-mesh
renderer in Godot.
"""

from pathlib import Path
from typing import Any

from PIL import Image, ImageOps

try:
    import cv2  # type: ignore
    import numpy as np
except Exception:  # pragma: no cover
    cv2 = None  # type: ignore
    np = None  # type: ignore


def capabilities() -> dict[str, Any]:
    return {"backend":"tps-cpu-v1","opencv":cv2 is not None,"numpy":np is not None,"supports_alpha":True,"non_destructive":True}


def _norm_point(p: dict[str, Any]) -> tuple[float, float]:
    return float(p.get("x",0.0)), float(p.get("y",0.0))


def _kernel(r2):
    return r2 * np.log(np.maximum(r2, 1e-12))


def _fit_tps(dst_ctrl, src_ctrl, regularization: float = 1e-5):
    n=int(dst_ctrl.shape[0]); diff=dst_ctrl[:,None,:]-dst_ctrl[None,:,:]
    k=_kernel(np.sum(diff*diff,axis=2))
    if regularization>0: k=k+np.eye(n,dtype=np.float64)*float(regularization)
    p=np.concatenate([np.ones((n,1),dtype=np.float64),dst_ctrl],axis=1)
    l=np.zeros((n+3,n+3),dtype=np.float64); l[:n,:n]=k; l[:n,n:]=p; l[n:,:n]=p.T
    y=np.zeros((n+3,2),dtype=np.float64); y[:n]=src_ctrl
    try: params=np.linalg.solve(l,y)
    except np.linalg.LinAlgError: params=np.linalg.lstsq(l,y,rcond=None)[0]
    return params[:n],params[n:]


def _eval_tps(points, ctrl, w, a):
    out=a[0]+points@a[1:]; result=np.empty((points.shape[0],2),dtype=np.float64); chunk=180_000
    for start in range(0,points.shape[0],chunk):
        stop=min(points.shape[0],start+chunk); q=points[start:stop]
        diff=q[:,None,:]-ctrl[None,:,:]; u=_kernel(np.sum(diff*diff,axis=2))
        result[start:stop]=out[start:stop]+u@w
    return result


def _fixed_anchors(width:int,height:int)->list[tuple[float,float]]:
    w,h=float(width-1),float(height-1)
    return [(0,0),(w*.5,0),(w,0),(0,h*.5),(w,h*.5),(0,h),(w*.5,h),(w,h)]


def warp_rgba(image:Image.Image,rest_joints:dict[str,dict[str,Any]],posed_joints:dict[str,dict[str,Any]],*,regularization:float=2e-4,fixed_border:bool=True,interpolation:str="cubic")->Image.Image:
    """Move artwork with the rig without generating new image content."""
    if np is None or cv2 is None: raise RuntimeError("mesh_deform requires numpy and opencv-python")
    im=ImageOps.exif_transpose(image).convert("RGBA"); width,height=im.size
    names=[name for name in rest_joints if name in posed_joints]
    if len(names)<3: return im.copy()
    src=[]; dst=[]
    for name in names:
        rx,ry=_norm_point(rest_joints[name]); px,py=_norm_point(posed_joints[name])
        src.append((rx*(width-1),ry*(height-1))); dst.append((px*(width-1),py*(height-1)))
    if fixed_border:
        anchors=_fixed_anchors(width,height); src.extend(anchors); dst.extend(anchors)
    src_ctrl=np.asarray(src,dtype=np.float64); dst_ctrl=np.asarray(dst,dtype=np.float64)
    if np.max(np.abs(src_ctrl-dst_ctrl))<1e-5: return im.copy()
    weights,affine=_fit_tps(dst_ctrl,src_ctrl,regularization=regularization)
    yy,xx=np.mgrid[0:height,0:width]; pts=np.column_stack([xx.reshape(-1),yy.reshape(-1)]).astype(np.float64)
    mapped=_eval_tps(pts,dst_ctrl,weights,affine)
    map_x=mapped[:,0].reshape(height,width).astype(np.float32); map_y=mapped[:,1].reshape(height,width).astype(np.float32)
    flag=cv2.INTER_CUBIC if interpolation=="cubic" else cv2.INTER_LINEAR
    arr=np.asarray(im,dtype=np.uint8)
    warped=cv2.remap(arr,map_x,map_y,flag,borderMode=cv2.BORDER_CONSTANT,borderValue=(0,0,0,0))
    return Image.fromarray(warped,"RGBA")


def warp_file(source:str|Path,destination:str|Path,rest_joints:dict[str,dict[str,Any]],posed_joints:dict[str,dict[str,Any]],**kwargs:Any)->dict[str,Any]:
    source=Path(source); destination=Path(destination); destination.parent.mkdir(parents=True,exist_ok=True)
    with Image.open(source) as opened:
        out=warp_rgba(opened,rest_joints,posed_joints,**kwargs); out.save(destination,"PNG",optimize=True)
    return {"path":str(destination),"width":out.width,"height":out.height,"backend":"tps-cpu-v1"}
