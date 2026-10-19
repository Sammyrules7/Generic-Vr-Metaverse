shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 moon_direction = vec3(-0.55, 0.46, -0.7);
varying vec3 world_position;

float hash(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.1, 0.3, 0.7));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x),
        mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
        mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
        mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

float cloud_top(vec3 position) {
    vec3 p = vec3(position.x * 0.032 - TIME * 0.007, 1.0, position.z * 0.032 - TIME * 0.0025);
    return -8.0 + noise(p) * 9.0;
}

float density(vec3 position) {
    if (position.y <= -18.0) { return 0.0; }
    float top = cloud_top(position);
    float vertical = smoothstep(-18.0, -12.0, position.y) * (1.0 - smoothstep(top - 4.0, top + 0.2, position.y));
    if (vertical <= 0.0) { return 0.0; }
    vec3 p = position * vec3(0.04, 0.095, 0.04) - vec3(TIME * 0.009, 0.0, TIME * 0.003);
    float billows = noise(p) * 0.62 + noise(p * 2.07 + 7.0) * 0.26 + noise(p * 4.1) * 0.12;
    return smoothstep(0.34, 0.7, billows) * vertical;
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float rise = cloud_top(world_position) + 1.0 - world_position.y;
    VERTEX.y += rise;
    world_position.y += rise;
}

void fragment() {
    float edge = 1.0 - smoothstep(165.0, 215.0, length(world_position.xz));
    // The square mesh extends beyond the circular bank. Those pixels are invisible.
    if (edge <= 0.0) { discard; }
    vec3 ray = normalize(world_position - CAMERA_POSITION_WORLD);
    float step_length = min(1.1 / max(abs(ray.y), 0.06), 7.0);
    vec3 light_direction = normalize(moon_direction);
    vec3 radiance = vec3(0.0);
    float opacity = 0.0;
    // Front-to-back samples through a shallow cloud bank, with light-facing
    // density probes to give the puffs shaded sides and illuminated tops.
    for (int i = 0; i < 12; i++) {
        vec3 p = world_position + ray * (float(i) + 0.5) * step_length;
        float cloud = density(p);
        // Empty samples contribute neither opacity nor radiance.
        if (cloud <= 0.0) { continue; }
        float edge_light = clamp((cloud - density(p + light_direction * 3.0)) * 2.3 + 0.5, 0.0, 1.0);
        vec3 color = mix(vec3(0.065, 0.095, 0.15), vec3(0.23, 0.3, 0.41), edge_light);
        float sample_opacity = 1.0 - exp(-cloud * step_length * 0.3);
        radiance += (1.0 - opacity) * color * sample_opacity;
        opacity += (1.0 - opacity) * sample_opacity;
    }
    ALBEDO = radiance / max(opacity, 0.001);
    ALPHA = opacity * edge;
}
