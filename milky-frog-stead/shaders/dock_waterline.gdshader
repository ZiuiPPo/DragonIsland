shader_type canvas_item;
render_mode unshaded;
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec2 rect_origin;
uniform vec2 rect_size = vec2(1.0);
varying vec2 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
void fragment() {
 vec4 c = texture(TEXTURE, UV);
 vec2 uv = (world_position - rect_origin) / rect_size;
 float water = texture(mask_tex, uv).a;
 // Keep deck and handrail dry. Only the low bucket/feet intersect the water.
 float lower = smoothstep(0.83, 0.98, UV.y + sin(TIME * 1.6) * 0.012);
 c.a *= 1.0 - water * lower * 0.85;
 COLOR = c;
}
