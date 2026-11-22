// 바닥 그림: 같은 바닥의 두 변형(a·b)을 세계 좌표 잡음으로 섞는다 — 4칸마다 끊기던 직선 이음매 대신 불규칙한 얼룩 경계.
// 경계는 그림 밝기를 따라 비틀어(밝은 돌·풀잎이 먼저 드러남) 겹쳐 비치는 이중 그림 없이 또렷하다.
// UV = 변형 a 조각, UV2 = 변형 b 조각(변형이 하나면 같은 조각). 정점 색 = 음영·어둠. 빛 없음.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D tex : source_color, filter_nearest;
// 얼룩 크기(칸): 클수록 큰 덩어리
uniform float patch_cells = 3.2;
// 경계 너비(0 = 칼같이, 클수록 부드럽게)
uniform float edge_soft = 0.05;

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

void fragment() {
	vec4 a = texture(tex, UV);
	vec4 b = texture(tex, UV2);
	vec2 p = wpos.xz / patch_cells;
	float m = vnoise(p) * 0.65 + vnoise(p * 2.7 + 17.3) * 0.25 + vnoise(p * 7.1 + 3.9) * 0.10;
	float la = dot(a.rgb, vec3(0.299, 0.587, 0.114));
	float lb = dot(b.rgb, vec3(0.299, 0.587, 0.114));
	float d = m - 0.5 + (lb - la) * 0.35;
	float t = smoothstep(-edge_soft, edge_soft, d);
	ALBEDO = mix(a.rgb, b.rgb, t) * COLOR.rgb;
}
