shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D viewport_texture : source_color;
uniform sampler2D right_eye_texture : source_color;
uniform bool stereo = false;

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
	if (stereo && reflection_eye > 0.5) {
		ALBEDO = texture(right_eye_texture, reflection_uv).rgb;
	} else {
		ALBEDO = texture(viewport_texture, reflection_uv).rgb;
	}
}
