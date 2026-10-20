shader_type spatial;
render_mode cull_disabled;
uniform vec4 cloth : source_color = vec4(0.09, 0.16, 0.15, 1.0);
void vertex() {
	float hem = pow(1.0 - UV.y, 2.0);
	VERTEX.z += sin(TIME * 0.8 + VERTEX.x * 2.5 + MODEL_MATRIX[3].z) * hem * 0.035;
}
void fragment() {
	float weave = 0.94 + 0.06 * sin(UV.x * 380.0) * sin(UV.y * 600.0);
	ALBEDO = cloth.rgb * weave;
	ROUGHNESS = 0.95;
}
