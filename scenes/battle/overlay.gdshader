// 바닥 위에 까는 표면 그림(물·얼음·진흙): 반투명. 칸 데이터 텍스처로 칸마다 표면을 찾는다.
// 가장자리(덩어리 방식, floor.gdshader와 같다): 둘레 3×3 칸이 칸 가운데에서 둥글게 퍼지는 영향을 주고, 표면 종류별 합과
// '표면 없음' 합 + 잡음 중 큰 쪽을 그린다 — 네모가 아니라 둥근 웅덩이. 높이가 다른 칸으로는 번지지 않는다.
// 물가 띠는 밝게(젖은 테), 그 안쪽 띠는 어둡게(깊이). dot_px > 0이면 1도트 격자에 맞춰 딱 끊는다.
// 정점 색 = 어둠, 색조·불투명도는 표면별 팔레트(tints).
// 물은 층을 나눠 그린다(반사 세기 reflect > 0인 표면 — 물·깊은 물·전기 물·얼음):
//   1) 물속: 표면 그림 × 색조, 물가에서 멀수록(깊을수록) 어둡고 진하게.
//   2) 반사: 도트 화면 거울 카메라(pixel_view — 물 높이 거울 아래에서 올려다본 세계, 빛과 그림자 층까지 입힌 그림)를
//      거울 위치(refl_mat)로 찾는다. 줄마다 1~2도트씩 가로로 흔들려(물결) 끊긴 띠로 비치고, 아무것도 없으면 하늘 색(기본 빛 따라 낮 ↔ 밤).
//      물가 쪽은 둑 그늘로 반사가 옅다.
//   3) 그림자: 드리운 그림자(shadow_tex)·수관 그늘(canopy) 아래에선 하늘 반사가 줄어 물이 어둡고 맑게(속이 비친다).
//   4) 빛 웅덩이 안 물은 퍼지는 빛을 덜 받게 미리 어둡게(반짝임 점·대시는 넣지 않는다 — 2026-11-28 사용자 결정).
//   5) 물가: 밝은 젖은 테 + 안쪽 깊이 띠.
// 그 위에 화면 빛과 그림자 층(pixel_light)이 한 번 더 씌워진다.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D tex : source_color, filter_nearest;
// 칸마다 RGBA8: r,g = 표면 그림 묶음의 첫 조각, b = 팔레트 번호 + 1(0 = 표면 없음)
uniform sampler2D surf : filter_nearest;
// 칸마다 RG8: r = 높이, g = 바닥 있음(1)
uniform sampler2D info : filter_nearest;
uniform ivec2 map_size = ivec2(1, 1);
uniform vec2 atlas_px = vec2(2048.0, 3328.0);
uniform float tile_px = 64.0;
uniform vec4 tints[8];
uniform float blob_radius = 1.3;
uniform float blob_noise = 0.5;
uniform float blob_jag = 0.14;
uniform float rim = 0.08;
uniform float dot_px = 0.0;
uniform float reflect[8];
// 표면 그림 방식(map_view.SURFACE_LOOK): 0 키트 그림 그대로 · 1 액체 웅덩이(기름·피·산·독·윤활유 — 본색 + 어두운 테 + 고정 윤기 줄, 기름은 무지갯빛 얼룩, 산·독은 거품)
//   · 2 진흙(젖은 짙은 웅덩이 + 마른 껍질 얼룩) · 3 얼음(키트 그림 + 갈라진 금 + 흰 서리 테). 색은 look_col(rgb 본색, a = 거품 0/1)
uniform float look[8];
uniform vec4 look_col[8];
// 반사(pixel_view.set_reflection·sync): 거울 카메라 그림, 그 투영×보기 행렬, 거울 높이
uniform bool refl_on = false;
uniform sampler2D refl_tex : filter_nearest;
uniform mat4 refl_mat;
uniform float refl_h = 0.0;
uniform vec3 sky_day = vec3(0.56, 0.66, 0.74);
uniform vec3 sky_night = vec3(0.05, 0.07, 0.11);
// 숲 맵(map_view — 둘레 지형 forest): 빈 반사 자리에 둘레 숲이 비친 짙은 청록 얼룩
uniform float sky_leafy = 0.0;
uniform vec3 leafy_dark = vec3(0.07, 0.15, 0.13);
uniform vec3 leafy_light = vec3(0.27, 0.42, 0.28);
// 빛 지도(map_view._build_lighting — pixel_light와 같다)
uniform bool light_on = false;
uniform sampler2D glow_tex : filter_linear;
uniform sampler2D linfo_tex : filter_linear;
uniform sampler2D shadow_tex : filter_linear;
uniform vec2 l_origin = vec2(0.0);
uniform vec2 l_size = vec2(1.0);
uniform bool canopy_on = false;
uniform sampler2D canopy : filter_linear;
uniform vec2 canopy_origin = vec2(0.0);
uniform vec2 canopy_size = vec2(1.0);

varying vec3 wpos;

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float blob_k(vec2 d) {
	float t = max(0.0, 1.0 - length(d) / blob_radius);
	return t * t;
}

void fragment() {
	vec2 p = wpos.xz;
	ivec2 c0 = clamp(ivec2(floor(p)), ivec2(0), map_size - 1);
	const float SIN_P = 0.7806247498;
	vec2 ps = dot_px > 0.0 ? vec2((floor(p.x * dot_px) + 0.5) / dot_px, (floor(p.y * SIN_P * dot_px) + 0.5) / (dot_px * SIN_P)) : p;
	vec2 tp = dot_px > 0.0 ? vec2(p.x, p.y * SIN_P) : p;  // 그림 1줄 = 화면 1도트 줄(floor.gdshader tex_p)
	vec2 i0 = round(texelFetch(info, c0, 0).rg * 255.0);
	// 표면 번호(0 = 없음)별 영향 합
	float wt[9];
	ivec4 sv[9];
	for (int j = 0; j < 9; j++) {
		wt[j] = 0.0;
		ivec2 c = c0 + ivec2(j % 3 - 1, j / 3 - 1);
		bool inside = all(greaterThanEqual(c, ivec2(0))) && all(lessThan(c, map_size));
		vec2 ic = inside ? round(texelFetch(info, c, 0).rg * 255.0) : vec2(-99.0, 0.0);
		sv[j] = inside && ic.g > 0.5 && ic.r == i0.r ? ivec4(round(texelFetch(surf, c, 0) * 255.0)) : ivec4(0);
	}
	for (int j = 0; j < 9; j++) {
		float k = blob_k(ps - (vec2(c0 + ivec2(j % 3 - 1, j / 3 - 1)) + 0.5));
		for (int i = 0; i <= j; i++) {
			if (sv[i].b == sv[j].b) {
				wt[i] += k;
				break;
			}
		}
	}
	int best = -1;
	float bw = -1e9;
	float sw = -1e9;
	for (int i = 0; i < 9; i++) {
		if (wt[i] <= 0.0) {
			continue;
		}
		vec2 o = vec2(float(sv[i].b) * 3.7, float(sv[i].b) * 1.9);
		float v = wt[i] + (vnoise(ps * 0.8 + o) - 0.5) * blob_noise + (vnoise(ps * 6.0 + o) - 0.5) * blob_jag;
		if (v > bw) {
			sw = bw;
			bw = v;
			best = i;
		} else if (v > sw) {
			sw = v;
		}
	}
	if (best < 0 || sv[best].b == 0) {
		discard;
	}
	ivec4 s = sv[best];
	ivec2 pc = ivec2(floor(tp));
	ivec2 tile = s.rg + ((pc % 4) + 4) % 4;
	vec4 col = texture(tex, (vec2(tile) + clamp(fract(tp), 0.004, 0.996)) * tile_px / atlas_px) * tints[s.b - 1];
	float lk = look[s.b - 1];
	float mg0 = bw - sw;  // 웅덩이 가장자리에서 안쪽까지(덩어리 여유)
	if (lk > 0.5) {
		vec4 lc = look_col[s.b - 1];
		float n1 = vnoise(ps * 2.2 + float(s.b) * 5.0);
		float n2 = vnoise(ps * 6.5 + float(s.b) * 9.0);
		if (lk < 1.5) {
			// 액체: 가운데 짙게, 테 한 단 밝게(젖은 둘레) — 단계로 끊는다
			vec3 base = lc.rgb * (mg0 > rim * 3.0 ? 0.78 : 1.0);
			if (mg0 < rim * 0.9) base = lc.rgb * 1.18 + 0.02;
			// 고정 윤기: 왼쪽 위로 비스듬한 짧은 밝은 줄(해 쪽)
			float st = fract((ps.x - ps.y * 0.6) * 3.0 + n1 * 0.8);
			if (st < 0.06 && n2 > 0.55 && mg0 > rim) base = mix(base, vec3(0.9), 0.35);
			if (lc.a > 0.5 && lc.a < 1.5) {
				// 거품: 칸마다 하나 커졌다 터진다
				vec2 bc = floor(ps * 5.0);
				float bh = hash(bc + float(s.b));
				float ph = fract(TIME * 0.7 + bh * 4.0);
				vec2 bp = (bc + 0.5 + (vec2(bh, hash(bc + 3.0)) - 0.5) * 0.5) / 5.0;
				if (bh > 0.7 && ph < 0.8 && abs(distance(ps, bp) * 32.0 - ph * 2.2) < 0.6 && mg0 > rim) base = lc.rgb * 1.6 + 0.08;
			} else if (lc.a >= 1.5) {
				// 기름: 천천히 도는 무지갯빛 얼룩(옅게)
				float h = vnoise(ps * 1.5 + vec2(TIME * 0.05, 0.0));
				vec3 sheen = 0.5 + 0.5 * cos(6.2831 * (h + vec3(0.0, 0.33, 0.67)));
				if (n1 > 0.6) base = mix(base, sheen * 0.45, 0.35);
			}
			col = vec4(base, 0.93);
		} else if (lk < 2.5) {
			// 진흙: 짙은 젖은 웅덩이 + 마른 껍질 얼룩, 가장자리는 옅게
			vec3 base = lc.rgb;
			if (n1 > 0.58) base *= 0.7;  // 고인 물
			else if (n2 > 0.66) base = base * 1.25 + 0.03;  // 마른 껍질
			if (n1 > 0.7 && n2 > 0.6) base = mix(base, vec3(0.75, 0.8, 0.82), 0.25);  // 고인 물 윤기
			col = vec4(base, mg0 < rim * 0.9 ? 0.75 : 0.9);
		} else {
			// 얼음: 키트 그림 위 갈라진 금 + 흰 서리 테
			vec2 g = floor(ps * 2.5);
			float d1 = 9.0;
			float d2 = 9.0;
			for (int j = -1; j <= 1; j++) {
				for (int i = -1; i <= 1; i++) {
					vec2 c = g + vec2(float(i), float(j));
					float dd = distance(ps * 2.5, c + vec2(hash(c), hash(c + 7.1)));
					if (dd < d1) { d2 = d1; d1 = dd; } else if (dd < d2) { d2 = dd; }
				}
			}
			if (d2 - d1 < 0.07) col.rgb = mix(col.rgb, vec3(0.92, 0.97, 1.0), 0.55);
			if (mg0 < rim * 0.9) col.rgb = mix(col.rgb, vec3(0.95, 0.98, 1.0), 0.6);
		}
	}
	float margin = bw - sw;
	float R = reflect[s.b - 1];
	// 빛 지도: 빛 단계·기본 빛·드리운 그림자·광원 빛
	vec3 linf = vec3(1.0, 0.0, 1.0);
	float shade = 1.0;
	vec3 glow = vec3(0.0);
	if (light_on) {
		vec2 luv = (ps - l_origin) / l_size;
		linf = texture(linfo_tex, luv).rgb;
		float sg = texture(shadow_tex, luv).r;
		shade = sg > 0.66 ? 1.0 : (sg > 0.33 ? 0.6 : 0.3);
		glow = texture(glow_tex, luv).rgb;
	}
	if (canopy_on) {
		float cs = texture(canopy, (ps - canopy_origin) / canopy_size).r;
		shade = min(shade, cs > 0.5 ? 0.4 : (cs > 0.15 ? 0.7 : 1.0));
	}
	if (R > 0.0 && margin >= rim * 0.5) {
		// 1) 물속: 깊을수록(물가에서 멀수록) 어둡고 진하게
		float deep = smoothstep(rim * 1.4, rim * 6.0, margin);
		col.rgb *= mix(0.9, 0.62, deep);
		col.a = mix(col.a, 0.97, deep * 0.6);
		// 2) 반사: 화면 줄(도트) 단위로 가로 흔들림(물결 줄무늬). 반짝임 점은 넣지 않는다(2026-11-28 사용자 결정)
		float row = floor(ps.y * SIN_P * max(dot_px, 32.0));
		float tq = floor(TIME * 6.0) / 6.0;
		float wob = sin(row * 0.83 + tq * 2.6) * sin(row * 0.29 - tq * 1.3);
		float off = round(wob * 1.6) / max(dot_px, 32.0);
		vec3 sky = mix(sky_night, sky_day, clamp(linf.b, 0.0, 1.0));
		if (sky_leafy > 0.0) {
			// 멀리 비친 숲: 잎 덩어리 얼룩(물결 흔들림을 같이 받아 줄무늬로 끊긴다), 기본 빛 따라 어둡게
			vec2 fp = vec2(ps.x + off, ps.y * 1.6);
			float fn = vnoise(fp * 1.3) * 0.65 + vnoise(fp * 3.7 + 4.1) * 0.35;
			vec3 fol = fn > 0.62 ? leafy_light : (fn > 0.45 ? mix(leafy_dark, leafy_light, 0.5) : leafy_dark);
			sky = mix(sky, fol * mix(0.35, 1.0, clamp(linf.b, 0.0, 1.0)), sky_leafy * 0.85);
		}
		sky *= mix(0.35, 1.0, shade);  // 3) 그늘 아래는 하늘이 덜 비친다
		vec3 refl = sky;
		float bright = 0.0;  // 밝게 비친 것(불·빛나는 것)은 물에 또렷하게
		if (refl_on) {
			vec4 cp = refl_mat * vec4(ps.x + off, 2.0 * refl_h - wpos.y, ps.y, 1.0);
			vec2 ruv = vec2(cp.x / cp.w * 0.5 + 0.5, 0.5 - cp.y / cp.w * 0.5);  // 그림 줄은 위에서부터
			if (all(greaterThan(ruv, vec2(0.0))) && all(lessThan(ruv, vec2(1.0)))) {
				vec4 rc = texture(refl_tex, ruv);
				refl = rc.rgb + sky * (1.0 - rc.a);  // 거울 그림은 검은 투명 바탕 위에 섞여 있다(미리 곱한 색)
				bright = smoothstep(0.55, 0.85, max(max(rc.r, rc.g), rc.b));
			}
		}
		refl = mix(refl, sky, 0.22 * (1.0 - bright));  // 물 위 옅은 하늘 빛(비친 그림이 검게 뚫리지 않게)
		float bank = smoothstep(rim * 0.5, rim * 3.0, margin);  // 물가 둑 그늘
		float rk = mix(R * mix(0.45, 1.0, bank), 0.85, bright);
		col.rgb = mix(col.rgb, refl * mix(vec3(0.8, 0.9, 0.95), vec3(1.0), bright), rk);
		// 빛 웅덩이 안: 화면 빛 층이 위에 퍼진 빛을 더하므로 물은 미리 어둡게(물은 퍼지는 빛을 덜 받는다 — 불빛 반사는 그대로)
		col.rgb *= 1.0 - 0.5 * clamp(max(max(glow.r, glow.g), glow.b), 0.0, 1.0) * (1.0 - bright);
	}
	if (margin < rim * 0.5) {
		col.rgb = mix(col.rgb, vec3(0.78, 0.88, 0.86), 0.5);  // 5) 물가 젖은 테
		col.a = max(col.a, 0.95);
	} else if (margin < rim * 1.4) {
		col.rgb *= 0.8;  // 안쪽 깊이 띠
	}
	ALBEDO = col.rgb * COLOR.rgb;
	ALPHA = col.a;
}
