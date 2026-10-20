shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, shadows_disabled;
void vertex() {
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 up = vec3(0.0, 1.0, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(up, 0.0), vec4(cross(right, up), 0.0), MODEL_MATRIX[3]);
}
void fragment() {
	float height = 1.0 - UV.y;
	float sway = sin(TIME * 8.0 + height * 5.0) * 0.065 * height;
	float width = mix(0.43, 0.015, pow(height, 0.7));
	float shape = 1.0 - smoothstep(width * 0.5, width, abs(UV.x - 0.5 + sway));
	float fade = smoothstep(0.0, 0.14, height) * (1.0 - smoothstep(0.83, 1.0, height));
	ALBEDO = mix(vec3(1.0, 0.28, 0.015), vec3(1.0, 0.94, 0.62), shape * (1.0 - height));
	EMISSION = ALBEDO * 2.4;
	ALPHA = shape * fade;
}
