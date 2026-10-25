shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform float fraction = -1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float filled = fraction >= 0.0 ? step(UV.x, fraction) : step(0.5, fract(UV.x * 4.0 - TIME * 1.5));
	ALBEDO = mix(vec3(0.078, 0.133, 0.216), vec3(0.627, 0.741, 0.831), filled);
	ALPHA = 0.9;
}
