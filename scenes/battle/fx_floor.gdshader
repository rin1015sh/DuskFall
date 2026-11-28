shader_type spatial;
// 바닥 효과(vfx.gd _floor): 바닥에 눕힌 판에 범위 효과의 바닥 부분을 그린다. 3D 바닥 위라 카메라 각도(세로 0.78 타원)와
// 실제 범위 크기(반지름 = 규칙 범위 N + 0.5칸)가 저절로 맞고, 세계 좌표를 그림 도트(1/32유닛)에 맞춰 찾아 지형 도트와 같은 굵기.
// 색은 원소별 5단 색 계단(ramp — 어두운 쪽 → 밝은 쪽, 게임 그림 색에서 뽑음), 부드러운 빛무리 없이 단계로 끊는다(빛은 효과 광원이 맡는다).
// style: 0 불(퍼지는 불 고리 → 그을린 바닥에 불씨) · 1 냉기(퍼지는 서리 고리 → 얼음 금 무늬 서리) · 2 회복(천천히 번지는 고리 + 안쪽 점선 원 + 떠오르는 빛 점)
//        3 번개(갈래 금 번쩍임 → 그을린 자국) · 4 광휘(밝은 원·도는 빛살) · 5 사령(검보라 웅덩이·핏줄 금) · 6 독·산성(얼룩 웅덩이·거품)
//        7 비전·역장(그려지며 도는 룬 고리 두 겹 → 충격파) · 8 천둥(동심 충격파 세 겹·흙먼지)
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
	float px1 = 1.0 / (radius * dot_px);  // 그림 1도트를 r 단위로 — 선 굵기는 범위 크기와 상관없이 도트로
	float fade = 1.0 - smoothstep(0.65, 1.0, t);
	if (style == 0) {
		float w = 1.0 * smoothstep(0.0, 0.3, t);  // 불 고리가 빠르게 퍼진다
		// 고리 앞머리: 잡음으로 찢긴 불 띠(두께 1~3도트), 지나간 자리는 얼룩진 그을음
		float edge = (vnoise(vec2(ang * 9.0 + seed, TIME * 3.0)) - 0.5) * 0.08;
		float band = r - w + edge;
		float n = vnoise(q * 2.4 + seed);
		float n2 = vnoise(q * 6.0 + seed * 2.0);
		if (r < 1.03) {
			if (band > -3.5 * px1 && band < 1.0 * px1 && t < 0.42 && n2 > 0.25) {
				col = n2 > 0.6 ? ramp[4] : ramp[3];
				a = 1.0;
			} else if (band > -7.0 * px1 && band < -3.5 * px1 && t < 0.5 && n2 > 0.45) {
				col = ramp[2];
				a = 1.0;
			} else if (band < -3.0 * px1) {
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
			if (band > -2.5 * px1 && band < 1.0 * px1 && t < 0.55 && n2 > 0.3) {
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
	} else if (style == 2) {
		float w = smoothstep(0.0, 0.55, t);
		float band = r - w;
		if (r < 1.02) {
			float ed = (vnoise(vec2(ang * 8.0 + seed, TIME)) - 0.5) * 0.04;
			if (abs(band + ed) < 1.2 * px1) {
				col = ramp[4];
				a = fade;
			} else if (band < 0.0) {
				// 안쪽 점선 원 두 겹(천천히 돈다)
				float rr = r;
				float ring = min(abs(rr - 0.62), abs(rr - 0.32));
				float dash = step(0.5, fract(ang * 6.0 / 3.14159 + TIME * 0.4 * (rr > 0.47 ? 1.0 : -1.0)));
				if (ring < 0.8 * px1 && dash > 0.5) {
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
	} else if (style == 3) {
		// 번개: 가운데에서 뻗는 갈래 번개(1도트 굵기, 마디마다 꺾이는 지그재그)가 몇 번 번쩍이고, 그을린 금이 남는다
		float beat = floor(t * 7.0);
		float flash = step(0.45, fract(t * 7.0)) * (1.0 - step(0.6, t));
		float bolt = 9.0;
		float rr = r * radius;  // 유닛
		for (int k = 0; k < 7; k++) {
			float kk = float(k);
			float a0 = kk * 0.898 + seed + beat * 0.45;
			// 마디(0.35유닛)마다 무작위 꺾임 — 마디 사이는 곧은 선
			float sg = floor(rr / 0.35);
			float f = fract(rr / 0.35);
			float j0 = (hash(vec2(sg, kk + beat * 13.0)) - 0.5) * 0.9;
			float j1 = (hash(vec2(sg + 1.0, kk + beat * 13.0)) - 0.5) * 0.9;
			float off = mix(j0, j1, f) * 0.35;  // 유닛
			float reach = 0.55 + hash(vec2(kk, seed + beat)) * 0.45;
			if (r < reach) {
				float da = mod(ang - a0 + 3.14159, 6.28318) - 3.14159;
				bolt = min(bolt, abs(da * rr - off));
			}
		}
		float n = vnoise(q * 3.0 + seed);
		float u1 = 1.0 / dot_px;
		if (bolt < 0.6 * u1 && flash > 0.5) {
			col = r < 0.35 ? ramp[4] : ramp[3];
			a = 1.0;
		} else if (bolt < 1.6 * u1 && flash > 0.5) {
			col = ramp[2];
			a = 0.7;
		} else if (bolt < 0.6 * u1 && t >= 0.6) {
			col = ramp[0];
			a = 0.55 * fade;  // 남은 그을린 금
		} else if (r < 0.35 && n > 0.6) {
			col = ramp[0];
			a = 0.4 * fade;
		}
	} else if (style == 4) {
		// 광휘: 가는 빛 고리가 번지고, 안쪽 절반에 가는 빛살이 돌며, 가운데 밝은 빛 웅덩이
		float w = smoothstep(0.0, 0.3, t);
		float edge = (vnoise(vec2(ang * 9.0 + seed, TIME)) - 0.5) * 0.03;
		float rayd = abs(fract(ang * 12.0 / 6.28318 + TIME * 0.12) - 0.5) * 6.28318 / 12.0 * r * radius;  // 빛살 가운데선까지 거리(유닛)
		if (r < w + 0.01) {
			if (abs(r - w + edge) < 1.2 * px1) {
				col = ramp[4];
				a = fade;
			} else if (rayd < 0.6 / dot_px && r > 0.1 && r < 0.6 * w && t < 0.8) {
				col = ramp[3];
				a = 0.75 * fade * (1.0 - r / 0.6);
			} else if (r < 0.18) {
				col = r < 0.09 ? ramp[4] : ramp[3];
				a = (r < 0.09 ? 0.8 : 0.5) * fade;
			} else if (vnoise(q * 2.5 + seed) > 0.62) {
				col = ramp[2];
				a = 0.18 * fade;
			}
		}
	} else if (style == 5) {
		// 사령: 검보라 웅덩이가 번지며 핏줄 같은 금이 뻗고, 가장자리 연기 테
		float w = smoothstep(0.0, 0.45, t);
		float edge = (vnoise(vec2(ang * 7.0 + seed, TIME * 0.5)) - 0.5) * 0.1;
		float band = r - w + edge;
		float n = vnoise(q * 2.2 + seed);
		float vein = cracks(q * 1.6);
		if (r < 1.05 && band < 0.0) {
			if (band > -2.0 * px1) {
				col = ramp[2];
				a = 0.8 * fade;
			} else if (vein < 0.6 * px1 * radius * 0.5 && vnoise(q * 1.3 + seed * 5.0) > 0.45) {
				col = ramp[3];
				a = 0.8 * fade;  // 핏줄 금(군데군데만)
			} else if (n > 0.38 - r * 0.15) {
				col = n > 0.55 ? ramp[0] : ramp[1];
				a = (0.4 + 0.25 * n) * fade;
			}
			float h = hash(floor(q * dot_px * 0.5) + seed);
			if (h > 0.975 && fract(TIME * 1.1 + h * 5.0) < 0.4) {
				col = ramp[4];
				a = fade;
			}
		}
	} else if (style == 6) {
		// 독·산성: 얼룩 웅덩이가 번지고 거품이 부글부글(둥근 거품이 생겼다 터진다)
		float w = smoothstep(0.0, 0.4, t);
		float m = vnoise(q * 2.0 + seed) * 0.7 + vnoise(q * 5.0 + seed) * 0.3 - r * 0.4 + (w - 0.5) * 0.5;
		if (r < 1.03 && m > 0.34) {
			col = m > 0.52 ? ramp[1] : ramp[0];
			a = (m > 0.52 ? 0.6 : 0.45) * fade;
			if (m < 0.355) {
				col = ramp[3];
				a = 0.8 * fade;  // 웅덩이 테
			}
			// 거품: 칸마다 하나, 커졌다 터진다
			vec2 bc = floor(q * 6.0);
			float bh = hash(bc + seed);
			float ph = fract(TIME * 0.8 + bh * 4.0);
			vec2 bp = (bc + 0.5 + (vec2(bh, hash(bc + 3.0)) - 0.5) * 0.5) / 6.0;
			float br = distance(q * vec2(1.0, 1.0), bp) * dot_px;
			float size = ph * 2.5;
			if (bh > 0.82 && m > 0.45 && ph < 0.85 && abs(br - size) < 0.6) {
				col = ramp[4];
				a = fade;
			}
		}
	} else if (style == 7) {
		// 비전·역장: 룬 고리 두 겹이 그려지며 돌고(눈금·룬), 끝에 충격파 고리가 퍼진다
		float draw_k = smoothstep(0.0, 0.35, t);
		float spin = TIME * 0.6;
		float aa = fract((ang + 3.14159) / 6.28318);
		float o1 = abs(r - 0.92);
		float o2 = abs(r - 0.62);
		float tick = step(0.7, fract(aa * 24.0 + spin));
		float rune = step(0.6, fract(aa * 10.0 - spin)) * step(fract(aa * 10.0 - spin), 0.9);
		float shock = abs(r - smoothstep(0.55, 0.95, t) * 1.05);
		if (aa < draw_k && t < 0.85) {
			if (o1 < 1.0 * px1 || o2 < 0.8 * px1) {
				col = o1 < 1.0 * px1 ? ramp[3] : ramp[4];
				a = 1.0;
			} else if (r > 0.8 && r < 0.86 && tick > 0.5) {
				col = ramp[2];
				a = 0.9;
			} else if (abs(r - 0.69) < 1.0 * px1 && rune > 0.5) {
				col = ramp[3];
				a = 0.9;
			} else if (r < 0.6) {
				col = ramp[1];
				a = 0.22;
			}
		}
		if (t > 0.55 && shock < 1.2 * px1 && r < 1.05) {
			col = ramp[4];
			a = 1.0 - smoothstep(0.8, 1.0, t);
		}
	} else {
		// 천둥: 동심원 충격파 세 겹이 차례로 퍼지고, 흙먼지 얼룩이 일어난다
		float n = vnoise(q * 3.0 + seed);
		for (int k = 0; k < 3; k++) {
			float tk = t - float(k) * 0.12;
			float w = smoothstep(0.0, 0.45, tk) * 1.02;
			float edge = (vnoise(vec2(ang * 10.0 + float(k), seed)) - 0.5) * 0.05;
			if (tk > 0.0 && tk < 0.55 && abs(r - w + edge) < (k == 0 ? 1.6 : 0.8) * px1) {
				col = k == 0 ? ramp[4] : ramp[3];
				a = 1.0 - smoothstep(0.35, 0.55, tk);
			}
		}
		if (a < 0.01 && r < smoothstep(0.0, 0.45, t) && n > 0.55 && r < 1.0) {
			col = n > 0.7 ? ramp[2] : ramp[1];
			a = 0.4 * fade;
		}
	}
	ALBEDO = col;
	ALPHA = a;
}
