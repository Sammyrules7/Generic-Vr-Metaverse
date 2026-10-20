shader_type spatial;
render_mode cull_disabled, depth_draw_never;
#include "res://worlds/moonlit_grotto/shaders/noise.gdshaderinc"
uniform float phase = 0.0;
void vertex() {
    VERTEX.x += (noise3(vec3(UV.y*5.0,TIME*.65,phase))-.5)*.16;
    VERTEX.z += (noise3(vec3(UV.y*7.0,TIME*.5,phase+9.0))-.5)*.1;
}
void fragment() {
    vec3 q = vec3(UV.x*23.0,UV.y*4.0-TIME*2.4,phase);
    float flow = fbm(q);
    float fine = noise3(vec3(UV.x*85.0,UV.y*9.0-TIME*5.0,phase));
    float edge_width = .09+(flow-.5)*.08;
    float edge = smoothstep(0.0,edge_width,UV.x)*smoothstep(0.0,edge_width,1.0-UV.x);
    float foam = smoothstep(.65,1.0,UV.y);
    ALBEDO = mix(vec3(.11,.3,.39),vec3(.66,.86,.91),flow*.65+fine*.2+foam*.2);
    EMISSION = ALBEDO*.14;
    ROUGHNESS = .32;
    ALPHA = edge * (.23+flow*.46+fine*.12+foam*.14);
}
