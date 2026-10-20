shader_type spatial;
render_mode cull_disabled;

uniform vec4 grass_color : source_color = vec4(0.7, 0.71, 0.42, 1.0);
uniform float wind_strength = 0.055;

void vertex() {
	// Vertex alpha anchors each blade at its roots; no CPU vegetation updates.
	float gust = sin(TIME * 1.4 + VERTEX.x * 0.25 + VERTEX.z * 0.18);
	VERTEX.x += gust * wind_strength * COLOR.a;
	VERTEX.z += cos(TIME * 1.1 + VERTEX.x * 0.18) * wind_strength * 0.4 * COLOR.a;
}

void fragment() {
	ALBEDO = grass_color.rgb * mix(0.78, 1.08, COLOR.a);
	ROUGHNESS = 0.95;
}
