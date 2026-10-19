shader_type spatial;
render_mode cull_disabled;
#include "res://worlds/moonlit_grotto/shaders/noise.gdshaderinc"
uniform vec3 deep_color : source_color = vec3(.018,.075,.10);
uniform vec3 crest_color : source_color = vec3(.07,.24,.27);
uniform float wave_scale = 1.0;
uniform bool lagoon = false;
varying vec2 basin_position;
varying vec3 water_position;
float wave(vec2 p) {
    vec3 q = vec3(p.x*.9,p.y*.9,TIME*.13);
    float warp = noise3(q*.43)*2.3;
    return fbm(q+vec3(warp,-warp,TIME*.035));
}
void vertex() {
    basin_position = VERTEX.xz;
    water_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    VERTEX.y += (wave(water_position.xz*.45)-.5)*.08*wave_scale;
}
void fragment() {
    if (lagoon && length((basin_position-vec2(0,1))/vec2(12,16)) > 1.0) { discard; }
    vec2 p = water_position.xz;
    float w = wave(p);
    float distant = smoothstep(25.0,130.0,length(VERTEX));
    NORMAL_MAP = vec3(.5,.5,1);
    // Beyond the fade, both expensive normal probes have zero contribution.
    if (distant < 1.0) {
        float dx = wave(p+vec2(.09,0))-w;
        float dz = wave(p+vec2(0,.09))-w;
        NORMAL_MAP = mix(normalize(vec3(-dx,-dz,.85))*.5+.5,vec3(.5,.5,1),distant);
    }
    ALBEDO = mix(deep_color,crest_color,w*.38);
    METALLIC = .18;
    ROUGHNESS = .3 + w*.12 + distant*.18;
    SPECULAR = .45;
}
