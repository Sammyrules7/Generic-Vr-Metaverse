shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D viewport_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D right_eye_texture : source_color, filter_linear, repeat_disable;
uniform bool stereo = false;
uniform sampler2D detail_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D right_detail_texture : source_color, filter_linear, repeat_disable;
uniform bool detail_enabled = false;
uniform bool close_detail = false;
uniform vec4 detail_left_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 detail_right_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 left_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 right_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);

// GLES emits VIEW_INDEX as uint even though the shading-language type is int.
// Convert explicitly; comparing it directly with a signed literal fails GLSL ES.
varying flat float reflection_eye;

void vertex() {
	reflection_eye = float(VIEW_INDEX);
}

void fragment() {
	// The off-axis cameras fit the glass itself, independently for each XR eye.
	// PlaneMesh's +Z UV direction is up on the glass; texture V points down.
	vec2 reflection_uv = vec2(UV.x, 1.0 - UV.y);
	bool right_eye = stereo && reflection_eye > 0.5;
	vec4 rect = right_eye ? right_uv_rect : left_uv_rect;
	vec2 sample_uv = (reflection_uv - rect.xy) / rect.zw;
	if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThan(sample_uv, vec2(1.0)))) {
		discard;
	}
	if (detail_enabled && !close_detail) {
		ALBEDO = right_eye ? textureLod(right_detail_texture, reflection_uv, 0.0).rgb : textureLod(detail_texture, reflection_uv, 0.0).rgb;
	} else if (right_eye) {
		ALBEDO = textureLod(right_eye_texture, sample_uv, 0.0).rgb;
	} else {
		ALBEDO = textureLod(viewport_texture, sample_uv, 0.0).rgb;
	}
	if (detail_enabled && close_detail) {
		vec4 detail_rect = right_eye ? detail_right_rect : detail_left_rect;
		vec2 detail_uv = (reflection_uv - detail_rect.xy) / detail_rect.zw;
		float edge = min(min(detail_uv.x, 1.0 - detail_uv.x), min(detail_uv.y, 1.0 - detail_uv.y));
		if (edge > 0.0) {
			vec3 sharp = right_eye ? textureLod(right_detail_texture, detail_uv, 0.0).rgb : textureLod(detail_texture, detail_uv, 0.0).rgb;
			ALBEDO = mix(ALBEDO, sharp, smoothstep(0.0, 0.08, edge));
		}
	}
}
