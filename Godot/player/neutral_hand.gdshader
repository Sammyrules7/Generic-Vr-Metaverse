shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.76, 0.86, 0.94, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
varying float tip;

void vertex() {
	tip = INSTANCE_CUSTOM.r;
}

void fragment() {
	float edge = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	ALBEDO = mix(tint.rgb, vec3(1.0), tip * 0.7);
	ALPHA = opacity * mix(0.045 + edge * 0.34, 0.10 + edge * 0.88, tip);
}
