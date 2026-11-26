shader_type canvas_item;
// 도트 화면 후처리(pixel_view.gd): 초표본 평균 → 제한된 팔레트(assets/pixel/palette.png)로 색 줄이기 + 4×4 Bayer 디더링.
// TEXTURE = 도트 SubViewport(lo_size × ss px). 한 도트 = ss×ss 화소 평균.
// 팔레트 고르기는 Oklab 거리(사람 눈에 가까운 색 차이). 디더는 밝기(L)에만 흔들어 색 점이 튀지 않게 한다.

uniform vec2 lo_size = vec2(320.0, 180.0);
uniform int ss = 2;
uniform int pal_count = 0;  // 0이면 색 줄이기 없음
uniform vec3 pal_rgb[128];
uniform vec3 pal_lab[128];
uniform float dither = 0.06;  // 밝기 흔들림 폭(Oklab L)
uniform ivec2 origin_px = ivec2(0);
// 줄여 그리면 가는 먹선이 평균에 묻혀 흐려 보이므로 대비·채도를 조금 올린다
uniform float contrast = 1.1;
uniform float saturation = 1.12;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

vec3 oklab(vec3 c) {
	vec3 l = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
	vec3 lms = vec3(
		dot(l, vec3(0.4122214708, 0.5363325363, 0.0514459929)),
		dot(l, vec3(0.2119034982, 0.6806995451, 0.1073969566)),
		dot(l, vec3(0.0883024619, 0.2817188376, 0.6299787005)));
	lms = pow(max(lms, vec3(0.0)), vec3(1.0 / 3.0));
	return vec3(
		dot(lms, vec3(0.2104542553, 0.7936177850, -0.0040720468)),
		dot(lms, vec3(1.9779984951, -2.4285922050, 0.4505937099)),
		dot(lms, vec3(0.0259040371, 0.7827717662, -0.8086757660)));
}

void fragment() {
	ivec2 px = ivec2(floor(UV * lo_size));
	px = clamp(px, ivec2(0), ivec2(lo_size) - 1);
	vec3 c = vec3(0.0);
	for (int j = 0; j < ss; j++) {
		for (int i = 0; i < ss; i++) {
			c += texelFetch(TEXTURE, px * ss + ivec2(i, j), 0).rgb;
		}
	}
	c /= float(ss * ss);
	float y = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(y), c, saturation);
	c = (c - 0.45) * contrast + 0.45;
	if (pal_count > 0) {
		ivec2 w = px + origin_px;
		ivec2 m = ((w % 4) + 4) % 4;
		float t = (BAYER[m.y * 4 + m.x] + 0.5) / 16.0 - 0.5;
		vec3 lab = oklab(clamp(c, 0.0, 1.0));
		lab.x += t * dither;
		float best = 1e9;
		vec3 pick = c;
		for (int k = 0; k < pal_count; k++) {
			vec3 d = lab - pal_lab[k];
			d.x *= 1.4;  // 밝기 차이를 조금 더 무겁게(형태 유지)
			float e = dot(d, d);
			if (e < best) {
				best = e;
				pick = pal_rgb[k];
			}
		}
		c = pick;
	}
	COLOR = vec4(c, 1.0);
}
