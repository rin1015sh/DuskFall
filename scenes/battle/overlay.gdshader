// 바닥 위에 까는 표면 그림(물·얼음·진흙): 반투명. 칸 데이터 텍스처로 칸마다 표면을 찾는다.
// 가장자리(덩어리 방식, floor.gdshader와 같다): 둘레 3×3 칸이 칸 가운데에서 둥글게 퍼지는 영향을 주고, 표면 종류별 합과
// '표면 없음' 합 + 잡음 중 큰 쪽을 그린다 — 네모가 아니라 둥근 웅덩이. 높이가 다른 칸으로는 번지지 않는다.
// 물가 띠는 밝게(젖은 테), 그 안쪽 띠는 어둡게(깊이). dot_px > 0이면 1도트 격자에 맞춰 딱 끊는다.
// 반짝임(shimmer): 표면별 세기만큼 물결 빛 점이 천천히 생겼다 사라진다(물 1, 얼음 0.4).
// 정점 색 = 어둠, 색조·불투명도는 표면별 팔레트(tints).
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
uniform float shimmer[8];
uniform float blob_radius = 1.3;
uniform float blob_noise = 0.5;
uniform float blob_jag = 0.14;
uniform float rim = 0.08;
uniform float dot_px = 0.0;

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
	float margin = bw - sw;
	if (margin < rim * 0.5) {
		col.rgb = mix(col.rgb, vec3(0.78, 0.88, 0.86), 0.5);  // 물가 젖은 테
		col.a = max(col.a, 0.95);
	} else if (margin < rim * 1.4) {
		col.rgb *= 0.8;  // 안쪽 깊이 띠
	}
	float sh = shimmer[s.b - 1];
	if (sh > 0.0 && margin > rim * 1.4) {
		// 물결 빛 점: 도트 2×1 크기, 자리마다 다른 주기로 잠깐 반짝
		vec2 cell = floor(ps * vec2(16.0, 32.0));
		float ph = hash(cell);
		float t = fract(TIME * 0.35 + ph * 7.0);
		if (ph > 1.0 - 0.06 * sh && t < 0.18) {
			col.rgb = mix(col.rgb, vec3(0.9, 0.97, 1.0), 0.55);
		}
	}
	ALBEDO = col.rgb * COLOR.rgb;
	ALPHA = col.a;
}
