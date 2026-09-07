shader_type spatial;
render_mode unshaded, fog_disabled;
#include "res://worlds/moonlit_grotto/shaders/noise.gdshaderinc"
varying vec3 moon_position;
void vertex() {
    moon_position = normalize(VERTEX);
}
void fragment() {
    float maria = smoothstep(.35,.7,fbm(moon_position*7.0));
    float craters = noise3(moon_position*43.0);
    ALBEDO = vec3(.65,.77,.91)*(0.65+maria*.3+craters*.07);
    EMISSION = ALBEDO*1.3;
}
