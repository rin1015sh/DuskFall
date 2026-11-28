shader_type spatial;
// 간이 인형 안쪽 선(doll_rig.gd): 인형 카메라 앞 화면 가득 판. 앞에 겹친 부위(몸통 앞 팔, 다리 앞 다리) 가장자리 1화소를
// 제 색의 어두운 쪽으로 곱한다(sel-out — pixel_outline과 같은 방식). 바깥 윤곽(빈 바탕과 맞닿은 곳)은 맵 화면 외곽선이 두르니 건너뛴다.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mul, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float depth_range = 399.0;
uniform float depth_threshold = 1.6;
uniform vec3 line_mul = vec3(0.62, 0.58, 0.68);

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

float depth_at(ivec2 p, ivec2 lim) {
	return texelFetch(depth_tex, clamp(p, ivec2(0), lim), 0).r;
}

void fragment() {
	ivec2 lim = ivec2(VIEWPORT_SIZE) - 1;
	ivec2 p = ivec2(floor(FRAGCOORD.xy));
	float d = depth_at(p, lim);
	float far_n = d;
	ivec2 o[4] = ivec2[](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
	for (int i = 0; i < 4; i++) {
		float n = depth_at(p + o[i], lim);
		if (n < 0.999) {
			far_n = max(far_n, n);
		}
	}
	ALBEDO = d < 0.999 && (far_n - d) * depth_range > depth_threshold ? line_mul : vec3(1.0);
}
