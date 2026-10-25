shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform float fraction = -1.0;
uniform float aspect = 26.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
float capsule(vec2 point, float start, float end) {
	return length(point - vec2(clamp(point.x, start + 0.5, max(start + 0.5, end - 0.5)), 0.5)) - 0.5;
}
void fragment() {
	vec2 point = UV * vec2(aspect, 1.0);
	float edge = max(fwidth(point.y), 0.015);
	float mask = 1.0 - smoothstep(-edge, edge, capsule(point, 0.0, aspect));
	float start = 0.0;
	float end = max(1.0, fraction * aspect);
	if (fraction < 0.0) {
		float travel = 0.5 - 0.5 * cos(TIME * 3.5);
		start = travel * aspect * 0.72;
		end = start + aspect * 0.28;
	}
	float fill = 1.0 - smoothstep(-edge, edge, capsule(point, start, end));
	if (fraction == 0.0) { fill = 0.0; }
	ALBEDO = mix(vec3(0.078, 0.133, 0.216), vec3(0.627, 0.741, 0.831), fill);
	ALPHA = mask * 0.95;
}
