// 바닥 그림(칸 데이터 텍스처로 칸마다 바닥을 찾아 그린다).
// - 종류가 다른 바닥 경계(덩어리 방식): 둘레 3×3 칸이 저마다 칸 가운데에서 둥글게 퍼지는 영향(반경 blob_radius)을 주고,
//   같은 바닥끼리 더한 값 + 바닥마다 다른 잡음이 가장 큰 바닥을 그린다 — 칸 모양 네모가 아니라 둥글고 들쭉날쭉한 덩어리.
//   경계는 섞지 않고 딱 끊되(도트 그림), 어두운 쪽 바닥의 경계 띠에 그늘(밝은 바닥이 덮고 올라온 느낌).
//   dot_px > 0이면 경계를 1도트 격자에 맞춘다(도트 화면). 높이가 다른 칸·벽 칸은 끼지 않는다(절벽 가장자리는 그대로).
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
// 칸 데이터 (0,0)이 놓인 세계 칸(맵 둘레 그물은 맵 밖까지 덮는 칸 데이터를 쓴다)
uniform ivec2 cell_origin = ivec2(0, 0);
uniform vec2 atlas_px = vec2(2048.0, 3328.0);
uniform float tile_px = 64.0;
// 변형 얼룩 크기(칸)·경계 너비
uniform float patch_cells = 3.2;
uniform float edge_soft = 0.05;
// 덩어리: 칸 영향 반경(칸)·잡음 세기(큰 물결·잔 들쭉날쭉)·경계 그늘 띠(영향 차이)·그늘 세기
uniform float blob_radius = 1.3;
uniform float blob_noise = 0.22;
uniform float blob_jag = 0.16;
uniform float rim = 0.07;
uniform float edge_shade = 0.22;
// 경계를 맞출 도트 격자(칸당 도트 수, 0 = 맞추지 않음)
uniform float dot_px = 0.0;
// 수관 그늘(map_view._build_canopy): 나무 수관 아래 그늘 세기(R, 세계 좌표 → canopy_origin·canopy_px로 찾음).
// 그늘 안에 잎 사이로 드는 빛 점이 천천히 흐르고(바람), 세기는 두 단계로 끊는다(도트 그림).
uniform bool canopy_on = false;
uniform sampler2D canopy : filter_linear;
uniform vec2 canopy_origin = vec2(0.0);
uniform vec2 canopy_size = vec2(1.0);
uniform float canopy_dark = 0.36;
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

// 카메라가 내려다보는 각(sin) — 바닥 세로 1유닛이 화면에서 이만큼 눌린다
const float SIN_P = 0.7806247498;

// 그림을 입히는 좌표: 도트 화면이면 세로를 원근만큼 늘려(z × sin) 그림 1줄 = 화면 1도트 줄(바닥 도트가 빠지거나 얇아지지 않게).
// 그림 묶음이 칸보다 세로로 조금 길어지지만 이어 까는 바닥이라 드러나지 않는다.
vec2 tex_p(vec2 p) {
	return dot_px > 0.0 ? vec2(p.x, p.y * SIN_P) : p;
}

// 도트 격자에 맞춘 점: 가로는 세계 1/dot_px, 세로는 화면 도트 줄(z × sin 기준)
vec2 dot_snap(vec2 p) {
	return vec2((floor(p.x * dot_px) + 0.5) / dot_px, (floor(p.y * SIN_P * dot_px) + 0.5) / (dot_px * SIN_P));
}

// 칸 c의 바닥을 세계 점 p에 그린다(변형 a·b 얼룩 섞기)
vec3 floor_color(ivec2 c, vec2 p) {
	ivec4 t = cell_tiles(c);
	vec2 tp = tex_p(p);
	ivec2 pc = ivec2(floor(tp));
	vec2 f = fract(tp);
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

// 칸 가운데에서의 거리 → 영향(반경 밖 0)
float blob_k(vec2 d) {
	float t = max(0.0, 1.0 - length(d) / blob_radius);
	return t * t;
}

// 바닥 종류마다 다른 잡음(경계를 들쭉날쭉하게)
float blob_n(ivec4 t, vec2 p) {
	vec2 o = vec2(float(t.r * 7 + t.b * 3), float(t.g * 5 + t.a * 11)) * 1.37;
	return (vnoise(p * 1.1 + o) - 0.5) * blob_noise + (vnoise(p * 5.3 + o * 2.1) - 0.5) * blob_jag * 0.6 + (vnoise(p * 11.0 + o * 3.3) - 0.5) * blob_jag * 0.4;
}

void fragment() {
	vec2 p = wpos.xz;
	ivec2 c0 = clamp(ivec2(floor(p)) - cell_origin, ivec2(0), map_size - 1);
	vec2 ps = dot_px > 0.0 ? dot_snap(p) : p;
	ivec4 tl[9];
	float wt[9];
	bool ok[9];
	for (int j = 0; j < 9; j++) {
		ivec2 c = c0 + ivec2(j % 3 - 1, j / 3 - 1);
		ok[j] = j == 4 || can_blend(c, c0);
		tl[j] = ok[j] ? cell_tiles(c) : ivec4(-1);
		wt[j] = 0.0;
	}
	// 같은 바닥끼리 영향을 더한다(처음 나온 자리에 모은다)
	for (int j = 0; j < 9; j++) {
		if (!ok[j]) {
			continue;
		}
		float k = blob_k(ps - (vec2(c0 + cell_origin + ivec2(j % 3 - 1, j / 3 - 1)) + 0.5));
		for (int i = 0; i <= j; i++) {
			if (ok[i] && tl[i] == tl[j]) {
				wt[i] += k;
				break;
			}
		}
	}
	int best = 4;
	int second = -1;
	float bw = -1e9;
	float sw = -1e9;
	for (int i = 0; i < 9; i++) {
		if (!ok[i] || wt[i] <= 0.0) {
			continue;
		}
		float v = wt[i] + blob_n(tl[i], ps);
		if (v > bw) {
			sw = bw;
			second = best;
			bw = v;
			best = i;
		} else if (v > sw) {
			sw = v;
			second = i;
		}
	}
	ivec2 cb = c0 + ivec2(best % 3 - 1, best / 3 - 1);
	vec3 col = floor_color(cb, p);
	if (second >= 0 && second != best && tl[second] != tl[best] && bw - sw < rim) {
		vec3 other = floor_color(c0 + ivec2(second % 3 - 1, second / 3 - 1), p);
		// 어두운 쪽 바닥의 경계 띠에 그늘
		if (dot(col, vec3(0.299, 0.587, 0.114)) < dot(other, vec3(0.299, 0.587, 0.114))) {
			col *= 1.0 - edge_shade;
		}
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
			if (dot_px > 0.0) {
				// 도트 화면: 화면 방향에서 비추듯 입힌다(가로 = 세계 x, 세로 = 화면 줄) — 비탈 기울기로 그림이 늘어나 뭉개지지 않게
				float sy = (wpos.y * 0.625 - wpos.z * SIN_P) * 64.0;
				u = rock_frame.x + mod(floor(wpos.x * 64.0), rock_frame.z);
				v = rock_frame.y + mod(floor(-sy), rock_frame.w);
			}
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
	if (canopy_on) {
		float sh = texture(canopy, (ps - canopy_origin) / canopy_size).r;
		if (sh > 0.2) {
			vec2 q = ps + vec2(TIME * 0.12, TIME * 0.05);
			float leaf = vnoise(q * 2.6) * 0.6 + vnoise(q * 6.5 + 9.1) * 0.4;
			float hole = smoothstep(0.66, 0.7, leaf);  // 잎 사이 빛 점
			float band = sh > 0.55 ? 1.0 : 0.55;
			col *= 1.0 - canopy_dark * band * (1.0 - hole * 0.85);
		}
	}
	ALBEDO = col * COLOR.rgb * shade_gain;
}
