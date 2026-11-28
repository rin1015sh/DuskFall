shader_type spatial;
// 도트 외곽선(pixel_view.gd): 화면 가득 판. 화소마다 깊이를 보고, 두께(그림 1도트 = thick 화소) 안의
// 이웃 화소가 depth_threshold 유닛 넘게 멀면(물체의 가장자리) 그 화소를 어둡게 한다(안쪽 외곽선).
// 검은 선 대신 곱하기(sel-out): 가장자리 색을 그 물체 제 색의 어두운 쪽(살짝 차갑게)으로 — 밝은 곳·불 옆에선 따뜻한 갈색,
// 어두운 곳에선 거의 안 보인다. 화소 단위로 재고 두께만 1도트라 촘촘한 몬스터 도트도 윤곽을 따라 고른 굵기로 감싼다.
// 직교 투영이라 깊이 값(0~1)이 선형: 거리 차 = 깊이 차 × (far − near).
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mul, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float ss = 2.0;  // 외곽선 두께(화소) = 그림 1도트
uniform float depth_range = 119.0;
uniform float depth_threshold = 0.45;
uniform vec3 line_mul = vec3(0.5, 0.47, 0.56);

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

float depth_at(ivec2 p, ivec2 lim) {
	return texelFetch(depth_tex, clamp(p, ivec2(0), lim), 0).r * depth_range;
}

void fragment() {
	ivec2 lim = ivec2(VIEWPORT_SIZE) - 1;
	ivec2 p = ivec2(floor(FRAGCOORD.xy));
	float d = depth_at(p, lim);
	float far_n = d;
	int t = max(int(ss), 1);
	for (int i = 1; i <= 4; i++) {
		if (i > t) {
			break;
		}
		far_n = max(far_n, max(max(depth_at(p + ivec2(i, 0), lim), depth_at(p - ivec2(i, 0), lim)),
				max(depth_at(p + ivec2(0, i), lim), depth_at(p - ivec2(0, i), lim))));
	}
	ALBEDO = far_n - d > depth_threshold ? line_mul : vec3(1.0);
}
