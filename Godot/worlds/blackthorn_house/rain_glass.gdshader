shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
uniform vec3 tint : source_color = vec3(0.18, 0.29, 0.38);
float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	float lane = floor(uv.x * 64.0);
	float x = fract(uv.x * 64.0);
	float speed = 0.035 + hash(lane) * 0.055;
	float y = fract(uv.y * 1.6 - TIME * speed + hash(lane + 7.0));
	float drop = (1.0 - smoothstep(0.025, 0.13, abs(x - 0.5))) * smoothstep(0.72, 0.99, y);
	float frost = smoothstep(0.34, 0.50, abs(uv.x - 0.5)) + smoothstep(0.38, 0.5, abs(uv.y - 0.5));
	ALBEDO = tint + vec3(drop * 0.2);
	ROUGHNESS = 0.18 + frost * 0.2;
	METALLIC = 0.25;
	EMISSION = vec3(0.12, 0.22, 0.32) * drop * 0.3;
	ALPHA = 0.11 + drop * 0.32 + frost * 0.08;
}
