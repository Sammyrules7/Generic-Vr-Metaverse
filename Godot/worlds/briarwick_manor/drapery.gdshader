shader_type spatial;
render_mode cull_disabled;
uniform vec4 cloth : source_color = vec4(0.16, 0.28, 0.29, 1.0);
void vertex() {
	VERTEX.z += cos(UV.x * 31.4159) * 0.055;
	NORMAL = normalize(vec3(sin(UV.x * 31.4159) * 2.4, 0.0, 1.0));
	VERTEX.z += sin(TIME * 0.8 + UV.x * 4.0) * UV.y * UV.y * 0.02;
}
void fragment() {
	float hem = step(0.965, UV.y) + step(UV.y, 0.025);
	ALBEDO = mix(cloth.rgb, vec3(0.65, 0.45, 0.20), min(hem, 1.0));
	ROUGHNESS = 0.96;
}
