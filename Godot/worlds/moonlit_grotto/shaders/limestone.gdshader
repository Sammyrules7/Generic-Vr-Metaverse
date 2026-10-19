shader_type spatial;
#include "res://worlds/moonlit_grotto/shaders/noise.gdshaderinc"
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    vec3 p = world_position;
    float patch = fbm(p*.63);
    float strata = fbm(vec3(p.x*.7, p.y*3.4 + patch*2.5, p.z*.7));
    float grain = noise3(p*28.0);
    float wet = (1.0-smoothstep(-.25,.65+patch*.45,p.y)) * (.6+patch*.4);
    float moss = smoothstep(.3,.85,world_normal.y) * smoothstep(.42,.7,fbm(p*.95+8.0));
    ALBEDO = mix(vec3(.16,.20,.24),vec3(.32,.35,.38),strata*.65+patch*.25+grain*.1);
    ALBEDO = mix(ALBEDO,vec3(.085,.15,.105),moss*.8);
    ALBEDO *= mix(1.0,.65,wet);
    ROUGHNESS = mix(.94,.38,wet);
    // Dry rock stays still: no animated blanket projected over the island.
}
