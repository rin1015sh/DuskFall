// 바닥 위에 까는 그림(물·얼음·진흙 표면): 반투명, 정점 색 = 색조·어둠.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D tex : source_color, filter_nearest;

void fragment() {
	vec4 c = texture(tex, UV) * COLOR;
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
