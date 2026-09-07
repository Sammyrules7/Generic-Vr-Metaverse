// Smooth, non-periodic value noise shared by the natural materials.
float hash31(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
float noise3(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash31(i), hash31(i+vec3(1,0,0)), f.x),
                   mix(hash31(i+vec3(0,1,0)), hash31(i+vec3(1,1,0)), f.x), f.y),
               mix(mix(hash31(i+vec3(0,0,1)), hash31(i+vec3(1,0,1)), f.x),
                   mix(hash31(i+vec3(0,1,1)), hash31(i+vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
    return noise3(p)*0.57 + noise3(p*2.03+vec3(17.1,3.7,11.5))*.28
         + noise3(p*4.17+vec3(9.2,23.4,2.8))*.15;
}
