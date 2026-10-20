shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

varying vec3 particle_world_position;

void vertex() {
    particle_world_position = MODEL_MATRIX[3].xyz;
    vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
    VERTEX *= scale;
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
    vec2 p = (UV - 0.5) * 2.0;
    p.y += sin(p.x * 3.0 + TIME * 0.6) * 0.13;
    float r = length(p);
    float feather = exp(-r * r * 5.0) * (1.0 - smoothstep(0.55, 1.0, r));
    // A drifting particle can cross the emission ring; fade before it enters
    // the lounge rather than letting streaks pass through people's faces.
    float outside = smoothstep(14.8, 17.5, length(particle_world_position.xz));
    ALBEDO = vec3(0.58, 0.7, 0.82);
    ALPHA = feather * COLOR.a * outside;
}
