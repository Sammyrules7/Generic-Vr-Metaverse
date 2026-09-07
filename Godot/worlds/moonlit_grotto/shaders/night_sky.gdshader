shader_type sky;
#include "res://worlds/moonlit_grotto/shaders/noise.gdshaderinc"
uniform vec3 moon_direction = vec3(-.38,.48,-.79);
void sky() {
    vec3 d = normalize(EYEDIR);
    float height = max(d.y,0.0);
    vec3 color = mix(vec3(.035,.065,.105),vec3(.004,.009,.028),smoothstep(0.0,.65,height));
    float galactic = exp(-pow((d.x*.5+d.y*.72+d.z*.3-.13)*5.0,2.0));
    float dust = fbm(d*24.0);
    color += vec3(.045,.04,.095)*galactic*dust*smoothstep(.05,.4,height);
    // Scattered 3D cells avoid latitude stripes and the pole/seam of a UV star map.
    vec3 p = d*380.0;
    vec3 cell = floor(p);
    float seed = hash31(cell);
    vec3 offset = vec3(hash31(cell+17.0),hash31(cell+41.0),hash31(cell+73.0));
    float star = 1.0-smoothstep(.06,.19,length(fract(p)-offset));
    star *= step(.965,seed)*smoothstep(.02,.16,height);
    color += mix(vec3(.52,.7,1.0),vec3(1.0,.8,.58),hash31(cell+9.0))*star*1.8;
    float clouds = smoothstep(.53,.77,fbm(d*vec3(4.0,13.0,4.0)+vec3(.4,2.1,.8)));
    clouds *= smoothstep(0.0,.12,height)*(1.0-smoothstep(.55,.9,height));
    color = mix(color,vec3(.055,.08,.13),clouds*.65);
    float angle = max(0.0,dot(d,normalize(moon_direction)));
    color += vec3(.11,.18,.29)*pow(angle,110.0);
    COLOR = color;
}
