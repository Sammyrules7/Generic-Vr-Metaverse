shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D viewport_texture : source_color;

void fragment() {
	// The reflection camera shares the player camera's projection, so the view
	// lines up pixel-for-pixel in screen space. Mesh UV would stretch the whole
	// reflection across the glass and slide as the player moves.
	ALBEDO = texture(viewport_texture, SCREEN_UV).rgb;
}
