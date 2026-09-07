shader_type sky;

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

float nebula(vec3 p) {
    return noise(p) * 0.53 + noise(p * 2.03) * 0.27 + noise(p * 4.1) * 0.13 + noise(p * 8.2) * 0.07;
}

void sky() {
    vec3 d = normalize(EYEDIR);
    float elevation = max(d.y, 0.0);
    vec3 horizon = vec3(0.022, 0.04, 0.082);
    vec3 zenith = vec3(0.0015, 0.004, 0.013);
    COLOR = mix(horizon, zenith, pow(elevation, 0.4));
    // The galactic field stays fixed while the aurora and star intensity evolve.
    float galactic_latitude = dot(d, normalize(vec3(0.58, -0.76, -0.29)));
    float band = exp(-52.0 * galactic_latitude * galactic_latitude);
    float cloud = nebula(d * 9.0 + vec3(13.0));
    float dust = smoothstep(0.38, 0.65, nebula(d * 23.0));
    vec3 galactic_color = mix(vec3(0.055, 0.045, 0.12), vec3(0.085, 0.18, 0.23), cloud);
    COLOR += band * galactic_color * smoothstep(0.28, 0.75, cloud) * (1.0 - dust * 0.65);
    // Folded aurora curtains span the northern horizon, fading into violet tips.
    float azimuth = atan(d.x, -d.z);
    float flow = TIME * 0.055;
    float swept_azimuth = azimuth + 0.055 * sin(flow * 0.7);
    float base = 0.27 + 0.055 * sin(swept_azimuth * 4.0 + flow * 0.45) + 0.027 * sin(swept_azimuth * 11.0 + 1.0 - flow);
    float h = d.y - base;
    float curtain = smoothstep(-0.01, 0.035, h) * (1.0 - smoothstep(0.05, 0.27, h));
    float filaments = 0.3 + 0.7 * noise(vec3(swept_azimuth * 115.0 - flow * 3.0, h * 2.0 - flow, 4.0 + flow * 0.2));
    float folds = pow(0.5 + 0.5 * sin(swept_azimuth * 22.0 + sin(swept_azimuth * 9.0 + flow) * 2.0 - flow), 2.0);
    float reach = exp(-0.45 * azimuth * azimuth);
    vec3 aurora_color = mix(vec3(0.035, 0.34, 0.2), vec3(0.14, 0.05, 0.26), smoothstep(0.015, 0.17, h));
    COLOR += aurora_color * curtain * reach * filaments * (0.35 + folds * 0.65) * 0.7;
    // Fine stars and a sparse second population of brighter, warmer stars.
    vec3 grid = d * 260.0;
    vec3 cell = floor(grid);
    float star = 1.0 - smoothstep(0.025, 0.19, length(fract(grid) - 0.5));
    float seed = hash(cell);
    float twinkle = 0.8 + 0.2 * sin(TIME * (0.65 + seed * 0.75) + seed * 70.0);
    COLOR += vec3(0.65, 0.79, 1.0) * star * step(0.965, seed) * smoothstep(0.03, 0.2, d.y) * 2.5 * twinkle;
    vec3 bright_grid = d * 110.0;
    float bright_star = 1.0 - smoothstep(0.03, 0.16, length(fract(bright_grid) - 0.5));
    float bright_seed = hash(floor(bright_grid));
    float bright_twinkle = 0.78 + 0.22 * sin(TIME * 0.9 + bright_seed * 90.0);
    COLOR += vec3(1.0, 0.78, 0.48) * bright_star * step(0.985, bright_seed) * smoothstep(0.05, 0.2, d.y) * 3.5 * bright_twinkle;
    vec3 moon_dir = normalize(LIGHT0_DIRECTION);
    float moon_distance = length(d - moon_dir);
    COLOR += vec3(0.6, 0.74, 0.9) * exp(-moon_distance * 18.0) * 0.14;
    float craters = nebula(d * 380.0);
    vec3 lunar_surface = vec3(0.88, 0.86, 0.72) * (0.55 + craters * 0.55);
    COLOR = mix(COLOR, lunar_surface, 1.0 - smoothstep(0.026, 0.028, moon_distance));
    if (d.y < 0.0) {
        COLOR = mix(horizon, vec3(0.02, 0.035, 0.07), min(-d.y * 3.0, 1.0));
    }
}
