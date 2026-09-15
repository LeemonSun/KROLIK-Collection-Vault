from pathlib import Path

path = Path('character_import.py')
text = path.read_text(encoding='utf-8')

text = text.replace(
    'from rig_edit import apply_joint_overrides\n',
    'from cutout_matte import finalize_cutout_matte\nfrom rig_edit import apply_joint_overrides\n',
    1,
)
text = text.replace('CUTOUT_ALGORITHM_VERSION = 2', 'CUTOUT_ALGORITHM_VERSION = 3', 1)

start = text.index('def _prepare_cutout(image: Image.Image, mode: str) -> tuple[Image.Image, dict[str, Any]]:')
end = text.index('\ndef prepare_character_asset(', start)
new_func = '''def _prepare_cutout(image: Image.Image, mode: str) -> tuple[Image.Image, dict[str, Any]]:\n    normalized_mode = _normalize_cutout_mode(mode)\n    if _has_meaningful_alpha(image):\n        base = image.copy()\n        info = {\n            "method": "embedded-alpha",\n            "confidence": 1.0,\n            "review_required": False,\n            "foreground_share": round(_alpha_coverage(image), 6),\n            "warnings": [],\n        }\n        return finalize_cutout_matte(base, info)\n    if normalized_mode == "auto":\n        initial, initial_info = _uniform_border_cutout(image)\n        selected_image, selected_info = initial, initial_info\n        if bool(initial_info.get("review_required")):\n            refined = _center_grabcut_refine(image, initial)\n            if refined is not None:\n                refined_image, refined_info = refined\n                if float(refined_info.get("confidence", 0.0)) > float(initial_info.get("confidence", 0.0)):\n                    selected_image, selected_info = refined_image, refined_info\n        return finalize_cutout_matte(selected_image, selected_info)\n\n    opaque = image.copy()\n    opaque.putalpha(255)\n    return opaque, {\n        "method": "opaque-preserve",\n        "confidence": 0.0,\n        "review_required": True,\n        "foreground_share": 1.0,\n        "warnings": ["source_has_no_embedded_alpha"],\n        "matte_quality_version": 3,\n        "edge_cleanup_applied": False,\n        "edge_pixels": 0,\n        "edge_halo_score_before": 0.0,\n        "edge_halo_score_after": 0.0,\n        "matte_quality": 1.0,\n        "transparent_padding_pixels": 0,\n    }\n\n'''
text = text[:start] + new_func + text[end+1:]

old = '        "warnings": list(cutout_info.get("warnings", [])),\n    }\n'
new = '''        "warnings": list(cutout_info.get("warnings", [])),\n        "matte_quality_version": int(cutout_info.get("matte_quality_version", 0)),\n        "alpha_boundary_refined": bool(cutout_info.get("alpha_boundary_refined", False)),\n        "alpha_trimmed_pixels": int(cutout_info.get("alpha_trimmed_pixels", 0)),\n        "alpha_coverage_before": float(cutout_info.get("alpha_coverage_before", 0.0)),\n        "alpha_coverage_after": float(cutout_info.get("alpha_coverage_after", 0.0)),\n        "fringe_width_before": dict(cutout_info.get("fringe_width_before", {})) if isinstance(cutout_info.get("fringe_width_before", {}), dict) else {},\n        "fringe_width_after": dict(cutout_info.get("fringe_width_after", {})) if isinstance(cutout_info.get("fringe_width_after", {}), dict) else {},\n        "edge_cleanup_applied": bool(cutout_info.get("edge_cleanup_applied", False)),\n        "edge_pixels": int(cutout_info.get("edge_pixels", 0)),\n        "edge_halo_score_before": float(cutout_info.get("edge_halo_score_before", 0.0)),\n        "edge_halo_score_after": float(cutout_info.get("edge_halo_score_after", 0.0)),\n        "matte_quality": float(cutout_info.get("matte_quality", 0.0)),\n        "transparent_padding_pixels": int(cutout_info.get("transparent_padding_pixels", 0)),\n    }\n'''
if old not in text:
    raise SystemExit('return marker not found')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
print('KROLIK_CUTOUT_V3_PATCH status=ok')
