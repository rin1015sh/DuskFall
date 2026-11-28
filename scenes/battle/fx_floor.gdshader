shader_type spatial;
// 바닥 효과(vfx.gd _floor): 바닥에 눕힌 판에 범위 효과의 바닥 부분을 그린다. 3D 바닥 위라 카메라 각도(세로 0.78 타원)와
// 실제 범위 크기(반지름 = 규칙 범위 N + 0.5칸)가 저절로 맞고, 세계 좌표를 그림 도트(1/32유닛)에 맞춰 찾아 지형 도트와 같은 굵기.
// 색은 원소별 5단 색 계단(ramp — 어두운 쪽 → 밝은 쪽, 게임 그림 색에서 뽑음), 부드러운 빛무리 없이 단계로 끊는다(빛은 효과 광원이 맡는다).
// style: 0 불(퍼지는 불 고리 → 그을린 바닥에 불씨) · 1 냉기(퍼지는 서리 고리 → 얼음 금 무늬 서리) · 2 회복(천천히 번지는 고리 + 안쪽 점선 원 + 떠오르는 빛 점)
// t = 0..1(효과 진행), seed = 자리마다 다른 무늬.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform vec3 center = vec3(0.0);
uniform float radius = 2.5;
uniform float t = 0.0;
uniform int style = 0;
uniform float seed = 0.0;
uniform vec3 ramp[5];
uniform float dot_px = 32.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// 보로노이 가장자리(얼음 금): 가장 가까운 두 점 거리 차
float cracks(vec2 p) {
	vec2 g = floor(p);
	float d1 = 9.0;
	float d2 = 9.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = g + vec2(float(i), float(j));
			vec2 o = c + vec2(hash(c + seed), hash(c + seed + 7.1));
			float d = distance(p, o);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

void fragment() {
	vec2 q = (floor(wpos.xz * dot_px) + 0.5) / dot_px;  // 그림 도트 격자
	vec2 d = q - center.xz;
	float r = length(d) / radius;
	// 둘레를 도트 단위로 살짝 흔들어 컴퍼스 원처럼 보이지 않게
	float ang = atan(d.y, d.x);
	r += (vnoise(vec2(ang * 3.0 + seed, seed)) - 0.5) * 0.06;
	vec3 col = vec3(0.0);
	float a = 0.0;
	float fade = 1.0 - smoothstep(0.65, 1.0, t);
	if (style == 0) {
		float w = 1.0 * smoothstep(0.0, 0.3, t);  // 불 고리가 빠르게 퍼진다
		// 고리 앞머리: 잡음으로 찢긴 불 띠(두께 1~3도트), 지나간 자리는 얼룩진 그을음
		float edge = (vnoise(vec2(ang * 9.0 + seed, TIME * 3.0)) - 0.5) * 0.08;
		float band = r - w + edge;
		float n = vnoise(q * 2.4 + seed);
		float n2 = vnoise(q * 6.0 + seed * 2.0);
		if (r < 1.03) {
			if (band > -0.035 && band < 0.012 && t < 0.42 && n2 > 0.25) {
				col = n2 > 0.6 ? ramp[4] : ramp[3];
				a = 1.0;
			} else if (band > -0.09 && band < -0.035 && t < 0.5 && n2 > 0.45) {
				col = ramp[2];
				a = 1.0;
			} else if (band < -0.03) {
				// 그을음: 큰 얼룩 + 잔 얼룩이 겹친 곳만, 가장자리로 갈수록 드문드문
				float m = n * 0.7 + n2 * 0.3 - r * 0.25;
				if (m > 0.32) {
					col = m > 0.5 ? ramp[0] : ramp[1];
					a = (m > 0.5 ? 0.62 : 0.4) * fade;
				}
				float h = hash(floor(q * dot_px * 0.5) + seed);
				float fl = fract(TIME * 1.7 + h * 5.0);
				if (h > 0.965 && fl < 0.5 && t < 0.8) {
					col = h > 0.985 ? ramp[4] : ramp[3];
					a = fade;
				}
			}
		}
	} else if (style == 1) {
		float w = 1.0 * smoothstep(0.0, 0.38, t);
		float edge = (vnoise(vec2(ang * 11.0 + seed, seed)) - 0.5) * 0.07;
		float band = r - w + edge;
		float n = vnoise(q * 2.5 + seed);
		float n2 = vnoise(q * 7.0 + seed * 3.0);
		if (r < 1.03) {
			if (band > -0.03 && band < 0.01 && t < 0.55 && n2 > 0.3) {
				col = ramp[4];
				a = 1.0;
			} else if (band < -0.025) {
				// 서리: 얼룩진 서리 막 + 군데군데만 얼음 금(가운데·얼룩 짙은 곳), 가장자리는 서리 깃털처럼 드문드문
				float m = n * 0.65 + n2 * 0.35 - r * 0.3;
				float cr = cracks(q * 2.2);
				if (m > 0.22) {
					col = m > 0.42 ? ramp[3] : ramp[2];
					a = (m > 0.42 ? 0.5 : 0.3) * fade;
					if (cr < 0.05 && m > 0.32) {
						col = ramp[4];
						a = 0.8 * fade;
					}
				}
			}
		}
	} else {
		float w = smoothstep(0.0, 0.55, t);
		float band = r - w;
		if (r < 1.02) {
			float ed = (vnoise(vec2(ang * 8.0 + seed, TIME)) - 0.5) * 0.04;
			if (abs(band + ed) < 0.022) {
				col = ramp[4];
				a = fade;
			} else if (band < 0.0) {
				// 안쪽 점선 원 두 겹(천천히 돈다)
				float rr = r;
				float ring = min(abs(rr - 0.62), abs(rr - 0.32));
				float dash = step(0.5, fract(ang * 6.0 / 3.14159 + TIME * 0.4 * (rr > 0.47 ? 1.0 : -1.0)));
				if (ring < 0.016 && dash > 0.5) {
					col = ramp[3];
					a = 0.9 * fade;
				} else {
					float m = vnoise(q * 2.0 + seed) - rr * 0.3;
					col = ramp[2];
					a = (m > 0.35 ? 0.22 : 0.0) * fade;  // 옅은 풀빛 얼룩만
				}
				// 떠오르는 빛 점(바닥에서 깜빡)
				float h = hash(floor(q * dot_px * 0.5) + seed);
				if (h > 0.95 && fract(TIME * 0.9 + h * 7.0) < 0.35) {
					col = ramp[4];
					a = fade;
				}
			}
		}
	}
	ALBEDO = col;
	ALPHA = a;
}
