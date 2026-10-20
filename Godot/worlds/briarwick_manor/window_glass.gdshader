shader_type spatial;
render_mode cull_disabled, blend_mix, shadows_disabled;
void fragment() {
	vec2 p = vec2((UV.x - 0.5) * 1.64, UV.y * 2.42);
	if (p.y < 0.82 && length(vec2(p.x, 0.82 - p.y)) > 0.82) discard;
	float a = abs(fract(UV.x * 4.0 + UV.y * 6.0) - 0.5);
	float b = abs(fract(UV.x * 4.0 - UV.y * 6.0) - 0.5);
	float lead = 1.0 - smoothstep(0.012, 0.027, min(a, b));
	float border = step(0.42, abs(UV.x - 0.5));
	float rose = 1.0 - smoothstep(0.11, 0.13, length((UV - vec2(0.5, 0.27)) * vec2(1.0, 1.48)));
	float lane = floor(UV.x * 51.0);
	float rain = (1.0 - smoothstep(0.035, 0.09, abs(fract(UV.x * 51.0) - 0.5))) * pow(fract(UV.y * 2.0 - TIME * 0.15 + sin(lane * 17.0)), 18.0);
	vec3 tint = mix(vec3(0.20, 0.40, 0.52), vec3(0.68, 0.35, 0.11), max(border, rose));
	ALBEDO = mix(tint + rain * 0.5, vec3(0.065, 0.075, 0.085), lead);
	ROUGHNESS = 0.85;
	SPECULAR = 0.0;
	EMISSION = tint * 0.12;
	ALPHA = max(lead * 0.85, 0.13 + border * 0.26 + rose * 0.25 + rain * 0.4);
}
