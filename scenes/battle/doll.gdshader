shader_type spatial;
// 간이 3D 인형(doll_rig.gd) 재질: 빛 없이(unshaded) 왼쪽 위(살짝 앞) 빛과 면 방향으로 3단 음영을 직접 끊는다.
//   밝은 단 = 본색 밝게·따뜻하게, 가운데 = 본색, 그늘 = 어둡게·차갑게. 도트 해상도 창에 그대로 찍혀 경계가 도트 계단.
//   pattern: 0 없음 · 1 사슬(밝은 점 격자) · 2 비늘(어두운 반달 줄) · 3 징(드문 밝은 점) · 4 단색(눈·입 — 음영 없음)
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec3 col : source_color = vec3(0.5);
uniform int pattern = 0;
uniform float pat_step = 2.0;
// 인형 세계 기준 빛 쪽: 왼쪽 위, 살짝 앞(카메라 쪽 +z) — 얼굴·가슴이 그늘에 묻히지 않게(도트 캐릭터 관례)
uniform vec3 light_dir = vec3(-0.55, 0.75, 0.35);

varying vec3 wn;
varying vec3 lp;

void vertex() {
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	lp = VERTEX;
}

void fragment() {
	vec3 c = col;
	if (pattern == 4) {
		ALBEDO = c;
	} else {
		float d = dot(normalize(wn), normalize(light_dir));
		vec3 hi = mix(c, vec3(1.0, 0.94, 0.78), 0.28);  // 밝은 색(판금)도 하얗게 날아가지 않게 섞기
		vec3 lo = mix(c * 0.62, vec3(0.18, 0.2, 0.34), 0.14);
		vec3 o = d > 0.62 ? hi : (d > 0.0 ? c : lo);
		if (pattern > 0 && pattern < 4) {
			vec2 g = lp.xy / pat_step;
			vec2 cell = floor(g);
			vec2 f = fract(g);
			if (pattern == 1) {
				if (mod(cell.x + cell.y, 2.0) < 0.5 && f.x < 0.5 && f.y < 0.5) o = mix(o, hi, 0.35);
			} else if (pattern == 2) {
				float sh = mod(cell.y, 2.0) * 0.5;
				if (fract(g.x + sh) > 0.6 && f.y > 0.55) o = mix(o, lo, 0.7);
			} else {
				if (mod(cell.x, 2.0) < 0.5 && mod(cell.y, 2.0) < 0.5 && f.x < 0.45 && f.y < 0.45) o = mix(o, vec3(0.85, 0.8, 0.66), 0.8);
			}
		}
		ALBEDO = o;
	}
}
