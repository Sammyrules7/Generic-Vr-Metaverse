shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
    float r = length((UV-vec2(.5))*2.0);
    float rings = pow(max(0.0,sin(r*42.0-TIME*3.0)),12.0);
    float fade = smoothstep(0.0,.25,r)*(1.0-smoothstep(.3,1.0,r));
    ALBEDO = vec3(.25,.65,.72);
    ALPHA = rings*fade*.3;
}
