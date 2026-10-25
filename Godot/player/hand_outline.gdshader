shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.77, 0.86, 0.93, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform vec3 fingertips[5];
uniform float fingertip_highlight = 0.0;
varying float tip_mask;

void vertex() {
	// Measure in the authored bind pose; the mask then follows skinning.
	float nearest_tip = 1000.0;
	for (int i = 0; i < 5; i++) {
		nearest_tip = min(nearest_tip, distance(VERTEX, fingertips[i]));
	}
	tip_mask = (1.0 - smoothstep(0.012, 0.035, nearest_tip)) * fingertip_highlight;
}

void fragment() {
	float edge = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	ALBEDO = mix(tint.rgb, vec3(1.0), tip_mask * 0.8);
	ALPHA = opacity * mix(0.10 + edge * 0.65, 0.26 + edge * 0.70, tip_mask);
}
