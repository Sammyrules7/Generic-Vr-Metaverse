shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 tint : source_color = vec4(0.25,0.85,1.0,1.0);
void vertex() {
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}
void fragment() {
    float r = length(UV - vec2(0.5)) * 2.0;
    ALBEDO = tint.rgb;
    ALPHA = pow(max(0.0,1.0-r),3.0) * COLOR.a * tint.a;
}
