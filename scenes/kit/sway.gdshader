shader_type spatial;
// 바람에 흔들리는 서 있는 그림 판(풀 덤불·꽃·나무 — kit3d.gd가 붙인다).
// 판 위쪽 두 꼭짓점만 옆으로 밀어 밑동은 땅에 붙은 채 기운다. 세기는 판 위 끝에서 amp 도트.
// 흔들림 = 자리마다 다른 잔물결 + 맵을 가로질러 천천히 지나가는 돌풍(바람은 서쪽에서 동쪽).
// 잎 덩어리(leaf > 0 — 나무·덤불): 수관(잎 화소)을 큰 덩어리(clump_px 크기 칸마다 하나, 원 + 잎 모양 들쭉날쭉한 가장자리)로 나눠
//   ① 덩어리마다 공처럼 3단 음영(북서쪽 빛 — 왼쪽 위 밝게·오른쪽 아래 그늘 테) ② 아래 덩어리가 앞(위 덩어리를 덮는다),
//   덩어리 사이 틈은 짙은 속 그늘 ③ 덩어리마다 다른 위상으로 바람에 흔들림(위쪽 덩어리일수록 크게, 도트 단위로 끊어).
//   그림 화소를 덩어리 자리만큼 옮겨 읽어 원래 잎 무늬는 살린다. 줄기·그림자·단풍(초록 아님)은 그대로.
// 깊이: 불투명 부분은 미리 깊이를 써서(외곽선·가림이 원래 판과 같다), 반투명 그림자 부분은 섞어 그린다.
// 판 색(빛 단계 어둠) = 정점 색(Sprite3D modulate).
render_mode unshaded, cull_disabled, depth_prepass_alpha, blend_mix;

uniform sampler2D texture_albedo : source_color, filter_nearest;
// 판 위 끝 흔들림(판 안 좌표 단위 — kit3d가 도트 → 판 단위로 바꿔 넣는다)
uniform float amp = 0.03;
uniform float speed = 1.0;
uniform float leaf = 0.0;
uniform vec2 sheet_px = vec2(1.0);
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);  // 시트 안 조각(px): x, y, w, h
uniform float clump_px = 22.0;

varying vec3 wpos;
varying float gust_v;
varying vec2 org_v;

void vertex() {
	vec2 o = MODEL_MATRIX[3].xz;
	float t = TIME * speed;
	float ripple = sin(t * 1.9 + o.x * 1.3 + o.y * 0.7) * 0.55 + sin(t * 3.1 + o.y * 1.9) * 0.25;
	float gust = smoothstep(-0.3, 1.0, sin(t * 0.55 - o.x * 0.32 - o.y * 0.12));
	float top = step(0.0, VERTEX.y);
	VERTEX.x += top * amp * (ripple * (0.45 + 0.55 * gust) + gust * 0.6);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	gust_v = gust;
	org_v = o;
}

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

// 조각 안 좌표(px) → 그림 색(조각 밖은 투명)
vec4 tex_at(vec2 q) {
	if (q.x < 0.0 || q.y < 0.0 || q.x >= frame_rect.z || q.y >= frame_rect.w) {
		return vec4(0.0);
	}
	return texture(texture_albedo, (frame_rect.xy + q) / sheet_px);
}

bool is_leaf(vec4 c) {
	return c.a > 0.5 && c.g > c.b * 1.05 && c.g > c.r * 0.97;
}

float lum(vec3 c) {
	return dot(c, vec3(0.3, 0.55, 0.15));
}

void fragment() {
	vec4 c = texture(texture_albedo, UV);
	if (leaf > 0.0) {
		vec2 p = UV * sheet_px - frame_rect.xy;
		p = floor(p * 0.5) * 2.0 + 1.0;  // 그림 1도트 = 2px 격자
		float S = clump_px;
		vec2 g0 = floor(p / S);
		float best_y = -1e9;
		vec4 best = vec4(0.0);
		vec3 base = vec3(0.0);
		float lit_b = 0.0;
		bool near = false;  // 수관 안(가까운 덩어리가 있다) — 이끼 낀 줄기는 속 그늘을 넣지 않는다
		float t = TIME * speed;
		for (int j = 0; j < 16; j++) {
			vec2 g = g0 + vec2(float(j % 4 - 1), float(j / 4 - 1));
			vec2 ctr = (g + 0.25 + 0.5 * vec2(hash(g), hash(g + 5.7))) * S;
			if (!is_leaf(tex_at(ctr))) {
				continue;
			}
			// 덩어리 본색: 가운데 둘레 다섯 점 평균(잎 화소만). 잎이 적으면(이끼 낀 줄기 등) 덩어리가 아니다
			vec3 acc = vec3(0.0);
			float n = 0.0;
			for (int k = 0; k < 5; k++) {
				vec2 sp = ctr + vec2(float(k % 3 - 1), float(k / 3 - 1) + (k == 4 ? 2.0 : 0.0)) * S * 0.25;
				vec4 sc = tex_at(sp);
				if (is_leaf(sc)) {
					acc += sc.rgb;
					n += 1.0;
				}
			}
			if (n < 4.0) {
				continue;
			}
			// 바람: 덩어리마다 위상이 다르고 위쪽일수록 크게, 도트 단위
			float hgt = clamp(1.0 - ctr.y / frame_rect.w, 0.0, 1.0);
			float ph = hash(g + 2.3) * 6.2831;
			float sway = sin(t * 1.6 + ph + org_v.x) * (0.6 + 0.6 * gust_v) + gust_v * 0.8;
			vec2 off = vec2(round(sway * (1.0 + 2.2 * hgt)) * 2.0, round(sin(t * 1.1 + ph * 1.7) * 0.6 * hgt) * 2.0);
			vec2 q = p - off;
			vec2 dv = (q - ctr) / (S * 0.8);
			float ang = atan(dv.y, dv.x);
			// 잎 모양 가장자리: 둥근 잎 뭉치 혹(각도 물결) + 도트 들쭉날쭉
			float d = length(dv) * (1.0 + 0.1 * sin(ang * 7.0 + ph) + 0.06 * sin(ang * 13.0 + ph * 2.0))
					+ (hash(floor(q / 2.0) + g) - 0.5) * 0.08;
			near = near || d < 1.5;
			if (d < 1.0 && ctr.y > best_y) {
				vec4 tc = tex_at(q);
				if (tc.a > 0.5 && (is_leaf(tc) || d < 0.7)) {
					best_y = ctr.y;
					best = tc;
					base = acc / n;
					// 공 음영: 북서쪽 위 빛
					float dd = min(d, 1.0);
					float nz = sqrt(max(0.0, 1.0 - dd * dd));
					lit_b = dot(normalize(vec3(dv, nz)), normalize(vec3(-0.55, -0.7, 0.55)));
					if (d > 0.84 && dv.x + dv.y > 0.15) {
						lit_b = -1.0;  // 오른쪽 아래 그늘 테(덩어리가 겹쳐 보이게)
					}
				}
			}
		}
		if (best_y > -1e8) {
			// 4단 음영 + 잎 점(원래 그림이 본색보다 확 밝거나 어두운 도트만 한 단 올리고 내림)
			float b = lit_b > 0.6 ? 3.0 : (lit_b > 0.15 ? 2.0 : (lit_b > -0.3 ? 1.0 : 0.0));
			float rel = lum(best.rgb) / max(lum(base), 0.02);
			if (rel > 1.3 && b < 3.0 && lit_b > -0.6) {
				b += 1.0;
			} else if (rel < 0.68 && b > 0.0) {
				b -= 1.0;
			}
			float f = b > 2.5 ? 1.2 : (b > 1.5 ? 0.98 : (b > 0.5 ? 0.74 : 0.52));
			vec3 col = base * f;
			if (b > 2.5) {
				col *= vec3(1.08, 1.06, 0.84);  // 밝은 쪽 따뜻하게
			} else if (b < 0.5) {
				col *= vec3(0.78, 0.9, 1.15);  // 그늘 쪽 차갑게
			}
			c = vec4(col, 1.0);
		} else if (near && is_leaf(c)) {
			c.rgb = c.rgb * 0.36 * vec3(0.8, 0.92, 1.15);  // 덩어리 사이 속 그늘
		}
	}
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a * COLOR.a;
}
