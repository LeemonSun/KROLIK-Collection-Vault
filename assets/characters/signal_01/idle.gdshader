shader_type canvas_item;
// Subtle procedural breathing/hair motion of the approved cutout, not a body rig.
uniform float motion : hint_range(0.0,1.0) = 1.0;
void fragment() {
 vec2 uv=UV;
 float hair=(1.0-smoothstep(0.36,0.50,uv.x))*smoothstep(0.15,0.30,uv.y)*(1.0-smoothstep(0.65,0.86,uv.y));
 float upper=(1.0-smoothstep(0.18,0.70,uv.y));
 uv.x+=motion*sin(TIME*1.35+uv.y*8.0)*0.0035*hair;
 uv.y+=motion*sin(TIME*1.55)*0.0016*upper;
 COLOR=texture(TEXTURE,uv)*COLOR;
}
