shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.77, 0.86, 0.93, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float has_masks = 0.0;
varying float hand_fade;
varying float tip_mask;

void vertex() {
	// Bind-pose masks are vertex attributes, so skinning cannot change them.
	hand_fade = mix(1.0, COLOR.r, has_masks);
	tip_mask = COLOR.g * has_masks;
}

void fragment() {
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float outline = smoothstep(0.62, 0.86, rim);
	float contrast_band = smoothstep(0.36, 0.57, rim) * (1.0 - outline);
	vec3 fill = mix(tint.rgb, vec3(1.0), tip_mask * 0.8);
	ALBEDO = mix(mix(fill, vec3(0.035, 0.055, 0.08), contrast_band), vec3(0.96, 0.99, 1.0), outline);
	float fill_alpha = mix(0.10, 0.30, tip_mask);
	ALPHA = opacity * hand_fade * max(fill_alpha, max(contrast_band * 0.65, outline * 0.96));
}
