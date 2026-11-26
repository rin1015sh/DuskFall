shader_type spatial;
// 도트 외곽선(pixel_view.gd): 화면 가득 판. 한 도트(ss×ss 화소) 단위로 깊이를 보고,
// 이웃 도트보다 depth_threshold 유닛 넘게 가까우면(물체의 가장자리 도트) 선 색으로 칠한다(안쪽 외곽선).
// 직교 투영이라 깊이 값(0~1)이 선형: 거리 차 = 깊이 차 × (far − near).
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float ss = 2.0;
uniform float depth_range = 119.0;
uniform float depth_threshold = 0.45;
uniform vec4 line_color : source_color = vec4(0.06, 0.05, 0.07, 0.85);

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

float dot_depth(ivec2 cell, ivec2 lim) {
	ivec2 p = clamp(cell * int(ss) + int(ss) / 2, ivec2(0), lim);
	return texelFetch(depth_tex, p, 0).r * depth_range;
}

void fragment() {
	ivec2 lim = ivec2(VIEWPORT_SIZE) - 1;
	ivec2 cell = ivec2(floor(FRAGCOORD.xy / ss));
	float d = dot_depth(cell, lim);
	float far_n = max(max(dot_depth(cell + ivec2(1, 0), lim), dot_depth(cell - ivec2(1, 0), lim)),
			max(dot_depth(cell + ivec2(0, 1), lim), dot_depth(cell - ivec2(0, 1), lim)));
	ALBEDO = line_color.rgb;
	ALPHA = far_n - d > depth_threshold ? line_color.a : 0.0;
}
