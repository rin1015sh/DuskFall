shader_type spatial;
// 화면에 씌우는 빛과 그림자(pixel_view.gd — 도트 카메라 앞 화면 가득 판 두 장).
// 화면 깊이로 세계 위치를 되짚어 빛 지도(map_view._build_lighting)를 찾는다:
//   glow_tex  RGB = 광원 빛(색 × 세기, 칸당 4화소)
//   info_tex  R = 빛 단계(0 어둠·0.5 어스름·1 밝음), B = 광원 뺀 기본 빛
//   shadow_tex = 드리운 그림자(1 없음 → 0 짙음, 높이가 바뀔 때만 다시 만든다)
// mode 0(곱하기 판): 밝은 곳은 살짝 따뜻하게, 어둑한 곳은 차갑게 + 드리운 그림자(차가운 그늘 색) + 가장자리 살짝 어둡게.
// mode 1(더하기 판): 광원 빛 웅덩이 — 세기를 3단계로 끊어 도트 경계가 또렷하게, 불은 일렁인다. 밝은 칸일수록 약하게.
// 세계 위치는 그림 도트(1/32유닛)에 맞춰 찾아 빛 경계가 도트 계단으로 끊긴다. 규칙(빛 단계·시야)은 바꾸지 않는다 — 그림만.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mul, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D glow_tex : filter_linear;
uniform sampler2D info_tex : filter_linear;
uniform sampler2D shadow_tex : filter_linear;
uniform vec2 l_origin = vec2(0.0);
uniform vec2 l_size = vec2(1.0);
uniform int mode = 0;
uniform bool on = false;
uniform float dot_px = 32.0;
uniform vec3 warm = vec3(1.0, 0.96, 0.88);
uniform vec3 dusk = vec3(0.86, 0.9, 1.0);
uniform vec3 night = vec3(0.8, 0.86, 1.0);
uniform vec3 shade = vec3(0.66, 0.7, 0.84);
uniform float vignette = 0.16;
uniform float glow_gain = 0.42;
// 효과 광원(pixel_view.set_dyn_lights): xy = 세계 x·z, z = 반지름(칸), w = 세기 / 색
uniform vec4 dyn_pos[8];
uniform vec4 dyn_col[8];
uniform int dyn_n = 0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec3 outc = mode == 0 ? vec3(1.0) : vec3(0.0);
	if (on && d < 0.99999) {
		vec3 ndc = vec3(SCREEN_UV, d) * 2.0 - 1.0;
		vec4 v = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		v /= v.w;
		vec3 w = (INV_VIEW_MATRIX * v).xyz;
		vec2 p = (floor(w.xz * dot_px) + 0.5) / dot_px;
		vec2 uv = (p - l_origin) / l_size;
		vec3 inf = texture(info_tex, uv).rgb;
		if (mode == 0) {
			float lv = inf.r;
			vec3 tint = lv > 0.5 ? mix(dusk, warm, (lv - 0.5) * 2.0) : mix(night, dusk, lv * 2.0);
			float sg = texture(shadow_tex, uv).r;
			float sh = sg > 0.66 ? 1.0 : (sg > 0.33 ? 0.55 : 0.0);  // 그림자 두 단계
			outc = tint * mix(shade, vec3(1.0), sh);
		} else {
			// 효과 광원: 둘레를 3단계로 끊어 더한다(빛 웅덩이와 같은 도트 경계)
			for (int k = 0; k < 8; k++) {
				if (k >= dyn_n) {
					break;
				}
				vec4 dp = dyn_pos[k];
				float dd = distance(p, dp.xy) / max(dp.z, 0.1);
				if (dd < 1.0) {
					float e = (1.0 - dd) * (1.0 - dd) * dp.w;
					float band = e > 0.5 ? 1.0 : (e > 0.25 ? 0.6 : (e > 0.08 ? 0.3 : 0.0));
					outc += dyn_col[k].rgb * band * 0.4 * (1.0 - 0.8 * inf.b);  // 밝은 맵에선 은은하게(빛 웅덩이와 같다)
				}
			}
			vec3 g = texture(glow_tex, uv).rgb;
			float i = max(max(g.r, g.g), g.b);
			if (i > 0.01) {
				float fl = 1.0 + 0.08 * sin(TIME * 7.3 + p.x * 2.1) * sin(TIME * 4.1 + p.y * 1.7);  // 일렁임
				float e = i * fl;
				float band = e > 0.62 ? 1.0 : (e > 0.36 ? 0.62 : (e > 0.14 ? 0.3 : 0.0));
				// 맵 기본 빛(광원 뺀)이 밝은 곳에서는 약하게, 어두운 곳일수록 빛 웅덩이가 산다
				outc += g / i * band * glow_gain * (1.0 - 0.75 * inf.b);
			}
		}
	}
	if (mode == 0) {
		float r = distance(SCREEN_UV, vec2(0.5));
		outc *= 1.0 - vignette * smoothstep(0.42, 0.78, r);
	}
	ALBEDO = outc;
}
