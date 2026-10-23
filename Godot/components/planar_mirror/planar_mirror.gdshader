shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D viewport_texture : source_color;
uniform sampler2D right_eye_texture : source_color;
uniform bool stereo = false;

void fragment() {
	// The off-axis cameras fit the glass itself, independently for each XR eye.
	// PlaneMesh's +Z UV direction is up on the glass; texture V points down.
	vec2 reflection_uv = vec2(UV.x, 1.0 - UV.y);
	if (stereo && VIEW_INDEX == 1) {
		ALBEDO = texture(right_eye_texture, reflection_uv).rgb;
	} else {
		ALBEDO = texture(viewport_texture, reflection_uv).rgb;
	}
}
