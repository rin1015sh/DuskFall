// 바닥 그림(칸 데이터 텍스처로 칸마다 바닥을 찾아 그린다).
// - 종류가 다른 바닥 경계: 위치를 잡음으로 흔들어(warp) 이웃 칸의 바닥을 가져온다 — 직선 경계 대신 들쭉날쭉 맞물림.
//   경계는 좁은 띠에서 그림 밝기를 따라 섞고(풀잎이 돌 위로 삐져나옴) 맞닿은 자리에 옅은 그늘.
//   높이가 다른 칸·벽 칸에서는 가져오지 않는다(절벽 가장자리는 그대로).
// - 같은 바닥의 두 변형(a·b): 세계 좌표 잡음 얼룩으로 섞는다(경계는 그림 밝기로 비틀어 또렷하게). 변형 b는 2칸 밀어 깐다.
// 그림 조각은 세계 좌표로 고르므로(4칸 묶음 그림의 나머지 조각) 칸 경계를 넘어도 무늬가 이어진다.
// - 자연 지형(rock_on): 가파른 곳(법선이 누운 곳)은 바위 그림(키트 바위 벽면)을 세계 좌표로 입혀 섞는다 — 절벽이 바닥과 한 그물.
//   캐릭터 앞(남쪽)을 가리는 가파른 곳은 체크무늬로 비친다(terrain.gdshader와 같다).
// 정점 색 = 음영·어둠. 빛 없음.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D tex : source_color, filter_nearest;
// 칸마다 RGBA8: r,g = 변형 a 묶음의 첫 조각(조각 단위), b,a = 변형 b
uniform sampler2D cells : filter_nearest;
// 칸마다 RG8: r = 높이, g = 바닥 있음(1)
uniform sampler2D info : filter_nearest;
uniform ivec2 map_size = ivec2(1, 1);
uniform vec2 atlas_px = vec2(2048.0, 3328.0);
uniform float tile_px = 64.0;
// 변형 얼룩 크기(칸)·경계 너비
uniform float patch_cells = 3.2;
uniform float edge_soft = 0.05;
// 종류 경계 흔들림(칸): 0이면 직선
uniform float warp = 0.36;
// 종류 경계 혼합 띠 너비(칸)·맞닿은 자리 그늘
uniform float blend_soft = 0.06;
uniform float edge_shade = 0.18;
// 섞을 수 있는 높이 차(블록 지형 0 = 같은 높이만, 자연 지형 1 = 언덕을 넘어서도)
uniform float blend_dh = 0.0;
// 정점 색 되돌림 배율(자연 지형: 평지 밝기를 1로, 빛 받는 비탈은 더 밝게)
uniform float shade_gain = 1.0;

// 자연 지형 바위: 켜기, 그림(벽면 시트), 묶음(px: x, y, 너비, 높이), 시트 크기
uniform bool rock_on = false;
uniform sampler2D rock_tex : source_color, filter_nearest;
uniform vec4 rock_frame = vec4(0.0, 0.0, 256.0, 160.0);
uniform vec2 rock_atlas = vec2(1024.0, 1024.0);
uniform vec4 actors[24];
uniform int actor_count = 0;

varying vec3 wpos;
varying vec3 wnormal;

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

ivec4 cell_tiles(ivec2 c) {
	return ivec4(round(texelFetch(cells, c, 0) * 255.0));
}

vec2 cell_info(ivec2 c) {
	return round(texelFetch(info, c, 0).rg * 255.0);
}

vec4 tile_tex(ivec2 tile, vec2 f) {
	return texture(tex, (vec2(tile) + clamp(f, 0.004, 0.996)) * tile_px / atlas_px);
}

ivec2 wrap4(ivec2 v) {
	return ((v % 4) + 4) % 4;
}

// 칸 c의 바닥을 세계 점 p에 그린다(변형 a·b 얼룩 섞기)
vec3 floor_color(ivec2 c, vec2 p) {
	ivec4 t = cell_tiles(c);
	ivec2 pc = ivec2(floor(p));
	vec2 f = fract(p);
	vec4 a = tile_tex(t.rg + wrap4(pc), f);
	vec4 b = tile_tex(t.ba + wrap4(pc + ivec2(2, 2)), f);
	vec2 q = p / patch_cells;
	float m = vnoise(q) * 0.65 + vnoise(q * 2.7 + 17.3) * 0.25 + vnoise(q * 7.1 + 3.9) * 0.10;
	float la = dot(a.rgb, vec3(0.299, 0.587, 0.114));
	float lb = dot(b.rgb, vec3(0.299, 0.587, 0.114));
	float d = m - 0.5 + (lb - la) * 0.35;
	return mix(a.rgb, b.rgb, smoothstep(-edge_soft, edge_soft, d));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

// 칸 c가 칸 c0와 섞일 수 있는가(지도 안·바닥·같은 높이)
bool can_blend(ivec2 c, ivec2 c0) {
	if (any(lessThan(c, ivec2(0))) || any(greaterThanEqual(c, map_size))) {
		return false;
	}
	vec2 ic = cell_info(c);
	return ic.g > 0.5 && abs(ic.r - cell_info(c0).r) <= blend_dh + 0.5;
}

void fragment() {
	vec2 p = wpos.xz;
	ivec2 c0 = clamp(ivec2(floor(p)), ivec2(0), map_size - 1);
	vec3 own = floor_color(c0, p);
	// 흔들린 위치(큰 물결 + 잔물결)
	vec2 w = vec2(vnoise(p * 1.3 + 11.0), vnoise(p * 1.3 + 47.0)) * 0.7
		+ vec2(vnoise(p * 4.1 + 3.0), vnoise(p * 4.1 + 29.0)) * 0.3 - 0.5;
	vec2 wp = p + w * 2.0 * warp;
	// 흔들린 점이 자기 칸 안쪽으로 얼마나 들어와 있나(+ 안, − 밖)와 맞은편 칸
	vec2 dlo = wp - vec2(c0);
	vec2 dhi = vec2(c0) + 1.0 - wp;
	float inside = min(min(dlo.x, dlo.y), min(dhi.x, dhi.y));
	ivec2 cn;
	if (inside < 0.0) {
		cn = ivec2(floor(wp));
	} else if (inside == dlo.x) {
		cn = c0 + ivec2(-1, 0);
	} else if (inside == dhi.x) {
		cn = c0 + ivec2(1, 0);
	} else if (inside == dlo.y) {
		cn = c0 + ivec2(0, -1);
	} else {
		cn = c0 + ivec2(0, 1);
	}
	vec3 col = own;
	if (cn != c0 && can_blend(cn, c0) && cell_tiles(cn) != cell_tiles(c0)) {
		vec3 other = floor_color(cn, p);
		float lo = dot(own, vec3(0.299, 0.587, 0.114));
		float ln = dot(other, vec3(0.299, 0.587, 0.114));
		// 경계 띠: 밝은 쪽(풀잎·돌 윗면)이 먼저 넘어온다
		float t = smoothstep(-blend_soft, blend_soft, -inside + (ln - lo) * 0.25);
		col = mix(own, other, t);
		// 맞닿은 자리에 옅은 그늘
		col *= 1.0 - edge_shade * (1.0 - abs(2.0 * t - 1.0));
	}
	if (rock_on) {
		vec3 n = normalize(wnormal);
		float rw = smoothstep(0.58, 0.38, n.y);
		if (rw > 0.001) {
			// 면 방향으로 감기: 남북을 보면 x, 동서를 보면 z를 따라. 단(160px)마다 가로로 어긋나게.
			float along = abs(n.z) >= abs(n.x) ? p.x : p.y;
			float band = floor(wpos.y * 40.0 / (rock_frame.w - 1.0));
			float u = rock_frame.x + mod(along * 64.0 + band * 97.0, rock_frame.z);
			float v = rock_frame.y + rock_frame.w - 0.5 - mod(wpos.y * 40.0, rock_frame.w - 1.0);
			vec3 rock = texture(rock_tex, vec2(u, v) / rock_atlas).rgb;
			vec2 q = vec2(along, wpos.y);
			rock *= mix(0.74, 1.08, vnoise(q * 0.8 + 5.0) * 0.7 + vnoise(q * 2.9) * 0.3);
			col = mix(col, rock, rw);
			if (rw > 0.35) {
				for (int i = 0; i < actor_count; i++) {
					vec4 a = actors[i];
					if (wpos.z > a.z + 0.35) {
						vec3 av = (VIEW_MATRIX * vec4(a.xyz, 1.0)).xyz;
						vec2 d = VERTEX.xy - av.xy;
						if (abs(d.x) < 0.42 * a.w && d.y > -0.3 && d.y < 1.6 * a.w) {
							if (mod(floor(FRAGCOORD.x) + floor(FRAGCOORD.y), 2.0) < 1.0) {
								discard;
							}
						}
					}
				}
			}
		}
	}
	ALBEDO = col * COLOR.rgb * shade_gain;
}
