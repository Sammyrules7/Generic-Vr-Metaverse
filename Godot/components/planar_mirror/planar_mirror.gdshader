shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D viewport_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D right_eye_texture : source_color, filter_linear, repeat_disable;
uniform bool stereo = false;
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
	if (right_eye) {
		ALBEDO = textureLod(right_eye_texture, sample_uv, 0.0).rgb;
	} else {
		ALBEDO = textureLod(viewport_texture, sample_uv, 0.0).rgb;
	}
}
