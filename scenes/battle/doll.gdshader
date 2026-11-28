shader_type spatial;
// 간이 3D 인형(doll_rig.gd) 재질: 빛 없이(unshaded) 왼쪽 위(살짝 앞) 빛과 면 방향으로 음영을 직접 끊는다 — 맵 키트 그림(반실사 어두운 판타지,
// 쿠와하라로 뭉친 붓 자국 같은 얼룩)에 맞게: 단 경계를 부위 자기 좌표의 뭉친 얼룩 잡음으로 흔들어 깔끔한 띠 대신 붓 자국 덩어리로,
// 재질마다 색 계단(kind): 0 피부(부드럽게·그늘 붉게) · 1 천(대비 낮게·결) · 2 가죽(따뜻·긁힌 결) · 3 쇠(대비 크게 — 어두운 반사 띠·작은 밝은 빛점·흠집)
// · 4 머리카락(결 줄) · 5 나무(결 줄). 색은 채도를 조금 낮추고 어둡게 눌러 맵 색과 맞춘다(그늘은 차갑게, 밝은 쪽은 따뜻하게).
//   pattern: 0 없음 · 1 사슬(고리 얼룩) · 2 비늘(반달 줄) · 3 징(드문 밝은 점) · 4 단색(눈 — 음영 없음) · 5 누빔(가로 홈) · 6 띠(굵은 가로 띠)
//   무늬·얼룩은 부위 자기 좌표(lp)로 — 움직여도 몸에 붙어 있다.
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec3 col : source_color = vec3(0.5);
uniform int pattern = 0;
uniform int kind = 0;
uniform float pat_step = 1.6;
// 인형 세계 기준 빛 쪽: 왼쪽 위, 살짝 앞(카메라 쪽 +z) — 얼굴·가슴이 그늘에 묻히지 않게(도트 캐릭터 관례)
uniform vec3 light_dir = vec3(-0.55, 0.75, 0.35);

varying vec3 wn;
varying vec3 lp;

void vertex() {
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	lp = VERTEX;
}

float h3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// 뭉친 얼룩(1~2도트 덩어리) — 칸 잡음 두 겹
float blot(vec3 p) {
	return h3(floor(p * 0.75)) * 0.6 + h3(floor(p * 0.32) + 7.0) * 0.4;
}

vec3 desat(vec3 c, float k) {
	float l = dot(c, vec3(0.3, 0.55, 0.15));
	return mix(c, vec3(l), k);
}

void fragment() {
	vec3 c = col;
	if (pattern == 4) {
		ALBEDO = c;
	} else {
		c = desat(c, 0.18) * 0.86;  // 맵 색에 맞춰 채도·밝기를 누름
		float n = blot(lp);
		float rough = kind == 3 ? 0.22 : (kind == 0 ? 0.14 : 0.34);
		float d = dot(normalize(wn), normalize(light_dir)) + (n - 0.5) * rough;
		if (kind == 4 || kind == 5) {
			// 결 줄: 머리카락·나무는 한 방향으로 긴 얼룩
			float st = h3(vec3(floor(lp.x * 0.9 + lp.z * 0.6), floor(lp.y * 0.22), 3.0));
			d += (st - 0.5) * 0.3;
		}
		vec3 warm = vec3(1.0, 0.9, 0.7);
		vec3 cool = vec3(0.16, 0.18, 0.3);
		vec3 o;
		if (kind == 3) {
			// 쇠: 가운데 어두운 반사 띠 + 밝은 쪽 끝에만 작은 빛점, 그늘은 깊고 차갑게
			vec3 deep = mix(c * 0.32, cool, 0.3);
			vec3 base = c * 0.72;
			vec3 band = mix(c * 0.5, cool, 0.12);
			vec3 hi = mix(c * 1.08, warm, 0.12);
			o = d > 0.8 ? mix(hi, vec3(1.0, 0.97, 0.88), 0.35) : (d > 0.5 ? hi : (d > 0.22 ? base : (d > 0.0 ? band : deep)));
			if (h3(floor(lp * 1.1) + 21.0) > 0.93) o *= 0.7;  // 흠집
		} else {
			float lo_k = kind == 0 ? 0.72 : 0.6;
			vec3 lo = kind == 0 ? mix(c * lo_k, vec3(0.42, 0.18, 0.2), 0.12) : mix(c * lo_k, cool, 0.16);
			vec3 deep = mix(c * 0.42, cool, 0.25);
			vec3 hi = mix(c * 1.1, warm, kind == 1 ? 0.06 : 0.1);
			o = d > 0.6 ? hi : (d > 0.12 ? c : (d > -0.35 ? lo : deep));
			if (kind == 1 || kind == 2) o *= 0.94 + h3(floor(lp * 0.9) + 5.0) * 0.1;  // 천·가죽 결
		}
		if (pattern != 0) {
			vec2 g = vec2(atan(lp.x, lp.z) * 2.2, lp.y) / pat_step;  // 둘레 방향 × 높이
			vec2 cell = floor(g);
			vec2 f = fract(g);
			if (pattern == 1) {
				float sh = mod(cell.y, 2.0) * 0.5;
				vec2 q = vec2(fract(g.x + sh), f.y) - 0.5;
				if (length(q) < 0.32) o *= 0.72;  // 고리 구멍
				else if (q.y < -0.2) o *= 1.12;
			} else if (pattern == 2) {
				float sh = mod(cell.y, 2.0) * 0.5;
				if (fract(g.x + sh) > 0.55 && f.y < 0.5) o *= 0.62;
			} else if (pattern == 3) {
				if (mod(cell.x, 2.0) < 0.5 && mod(cell.y, 2.0) < 0.5) o = mix(o, vec3(0.78, 0.72, 0.58), 0.7);
			} else if (pattern == 5) {
				if (mod(cell.y, 2.0) < 0.5) o *= 0.8;
			} else if (pattern == 6) {
				if (mod(cell.y, 3.0) < 0.5) o *= 0.6;
			}
		}
		ALBEDO = o;
	}
}
