shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
        mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
    vec2 p = UV * 18.0;
    float clouds = noise(p) * 0.6 + noise(p * 2.1) * 0.27 + noise(p * 4.3) * 0.13;
    ALBEDO = mix(vec3(0.13, 0.2, 0.32), vec3(0.37, 0.45, 0.6), clouds);
    float edge = 1.0 - smoothstep(0.32, 0.5, length(UV - vec2(0.5)));
    ALPHA = smoothstep(0.22, 0.72, clouds) * edge * 0.85;
}
