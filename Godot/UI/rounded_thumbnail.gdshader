shader_type canvas_item;

// Round the actual image quad, including thumbnails fitted inside wide cards.
uniform float radius = 8.0;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV) * tint;
	vec2 pixel_size = max(fwidth(UV), vec2(0.00001));
	vec2 image_size = 1.0 / pixel_size;
	float corner = min(radius, min(image_size.x, image_size.y) * 0.5);
	vec2 distance_to_edge = abs((UV - 0.5) * image_size) - image_size * 0.5 + corner;
	float distance_to_corner = length(max(distance_to_edge, vec2(0.0))) + min(max(distance_to_edge.x, distance_to_edge.y), 0.0) - corner;
	source.a *= 1.0 - smoothstep(-0.5, 0.5, distance_to_corner);
	COLOR = source;
}
