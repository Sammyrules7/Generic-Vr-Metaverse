shader_type sky;

float hash(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.1, 0.3, 0.7));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
    vec3 d = normalize(EYEDIR);
    float elevation = max(d.y, 0.0);
    vec3 horizon = vec3(0.045, 0.07, 0.135);
    vec3 zenith = vec3(0.002, 0.005, 0.015);
    COLOR = mix(horizon, zenith, pow(elevation, 0.4));
    float band = exp(-18.0 * abs(d.y - 0.35 * d.x - 0.42));
    COLOR += band * vec3(0.016, 0.029, 0.052);
    // Static sky avoids rebuilding the radiance cubemap every frame.
    vec3 grid = d * 260.0;
    vec3 cell = floor(grid);
    float star = smoothstep(0.19, 0.025, length(fract(grid) - 0.5));
    float seed = hash(cell);
    COLOR += vec3(0.65, 0.79, 1.0) * star * step(0.965, seed) * smoothstep(0.03, 0.2, d.y) * 2.5;
    vec3 moon_dir = normalize(vec3(-0.55, 0.46, -0.7));
    float moon_distance = length(d - moon_dir);
    COLOR += vec3(0.6, 0.74, 0.9) * exp(-moon_distance * 18.0) * 0.14;
    COLOR = mix(COLOR, vec3(1.0, 0.91, 0.73), 1.0 - smoothstep(0.026, 0.028, moon_distance));
    if (d.y < 0.0) {
        COLOR = mix(horizon, vec3(0.02, 0.035, 0.07), min(-d.y * 3.0, 1.0));
    }
}
