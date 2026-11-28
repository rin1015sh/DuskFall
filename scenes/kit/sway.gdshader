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

// 덩어리 안 잎 하나: 잎 격자(엇갈린 줄) 칸마다 잎 하나 — 덩어리 가운데에서 바깥·아래로 처진 뾰족한 잎
// u: 덩어리 가운데 기준 도트 좌표, rd: 덩어리 반지름(도트). 돌려줌: x = 맞음(1/0), y = 잎 가운데 y(앞뒤), z·w = 잎 가운데
vec4 leaf_at(vec2 u, float rd, vec2 gid, vec2 cpx, float t, float gust, out float tone_k, out float edge) {
	const vec2 LS = vec2(5.0, 3.5);  // 잎 격자(도트)
	float best = -1e9;
	vec4 res = vec4(0.0);
	tone_k = 0.0;
	edge = 0.0;
	float r0 = floor(u.y / LS.y);
	for (int j = 0; j < 9; j++) {
		float r = r0 + float(j / 3 - 1);
		float sh = mod(r, 2.0) * 0.5 * LS.x;
		float cx = floor((u.x - sh) / LS.x) + float(j % 3 - 1);
		vec2 id = vec2(cx, r);
		float h = hash(id + gid * 3.1);
		vec2 lc = (id + 0.5 + (vec2(h, hash(id + gid + 7.7)) - 0.5) * 0.8) * LS + vec2(sh, 0.0);
		// 잎 떨림: 잎마다 다른 박자로 가끔 1도트(돌풍 때 더 자주)
		float fl = sin(t * (2.6 + h * 2.0) + h * 40.0);
		lc.x += round(fl * (0.35 + 0.5 * gust));
		float lr = length(lc) / rd;
		if (lr > 1.0 + (h - 0.5) * 0.25) {
			continue;
		}
		// 판 가장자리에서 잘리지 않게: 잎이 통째로 조각 안에 들어가는 자리만(바람 흔들림 여유 포함)
		vec2 lpx = cpx + lc * 2.0;
		float mg = 12.0 + hash(id + gid + 9.1) * 16.0;  // 잎마다 다른 여유 — 가장자리가 곧은 줄로 늘어서지 않게
		if (lpx.x < mg || lpx.y < mg || lpx.x > frame_rect.z - mg || lpx.y > frame_rect.w - 12.0) {
			continue;
		}
		vec2 dir = normalize(lc / max(length(lc), 0.5) * 0.8 + vec2((hash(id + 3.3) - 0.5) * 0.9, 1.0));
		vec2 v = u - lc;
		float a = dot(v, dir);
		float b = dot(v, vec2(-dir.y, dir.x));
		float len = 3.4 + h * 1.4;
		float wid = 2.1 * (1.0 - 0.5 * clamp(a / len, -1.0, 1.0));
		float e = (a / len) * (a / len) + (b / wid) * (b / wid);
		if (e < 1.0 && lc.y > best) {
			best = lc.y;
			res = vec4(1.0, lc.y, lc);
			tone_k = h;
			// 잎 아래·오른쪽 끝 도트는 그늘(잎이 겹쳐 보이게), 위·왼쪽 끝은 밝은 테
			vec2 v2 = v + vec2(0.8, 0.8);
			float a2 = dot(v2, dir);
			float b2 = dot(v2, vec2(-dir.y, dir.x));
			float wid2 = 2.1 * (1.0 - 0.5 * clamp(a2 / len, -1.0, 1.0));
			vec2 v3 = v - vec2(0.8, 0.8);
			float a3 = dot(v3, dir);
			float b3 = dot(v3, vec2(-dir.y, dir.x));
			float wid3 = 2.1 * (1.0 - 0.5 * clamp(a3 / len, -1.0, 1.0));
			edge = (a2 / len) * (a2 / len) + (b2 / wid2) * (b2 / wid2) > 1.0 ? -1.0
					: ((a3 / len) * (a3 / len) + (b3 / wid3) * (b3 / wid3) > 1.0 ? 1.0 : 0.0);
		}
	}
	return res;
}

void fragment() {
	vec4 c = texture(texture_albedo, UV);
	if (leaf > 0.0) {
		vec2 p = UV * sheet_px - frame_rect.xy;
		p = floor(p * 0.5) * 2.0 + 1.0;  // 그림 1도트 = 2px 격자
		float S = clump_px;
		vec2 g0 = floor(p / S);
		float t = TIME * speed;
		// 1) 이 화소를 덮는 덩어리 넷까지 모은다
		vec4 cand[4];  // xy = 덩어리 안 좌표(도트, 바람 옮김 뺀), z = 덩어리 y, w = 반지름 비율
		vec2 cg[4];
		vec3 cb[4];
		vec2 cc[4];  // 덩어리 가운데(조각 px, 바람 옮김 포함)
		int nc = 0;
		bool near = false;
		for (int j = 0; j < 16; j++) {
			vec2 g = g0 + vec2(float(j % 4 - 1), float(j / 4 - 1));
			vec2 ctr = (g + 0.25 + 0.5 * vec2(hash(g), hash(g + 5.7))) * S;
			if (!is_leaf(tex_at(ctr))) {
				continue;
			}
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
				continue;  // 잎이 적은 자리(이끼 낀 줄기)는 덩어리 아님
			}
			float hgt = clamp(1.0 - ctr.y / frame_rect.w, 0.0, 1.0);
			float ph = hash(g + 2.3) * 6.2831;
			float sway = sin(t * 1.6 + ph + org_v.x) * (0.6 + 0.6 * gust_v) + gust_v * 0.8;
			vec2 off = vec2(round(sway * (1.0 + 2.2 * hgt)) * 2.0, round(sin(t * 1.1 + ph * 1.7) * 0.6 * hgt) * 2.0);
			vec2 u = (p - off - ctr) * 0.5;  // 도트
			float rd = S * 0.5 * 0.82;
			float d = length(u) / rd;
			near = near || d < 1.5;
			if (d < 1.25) {
				int slot = nc;
				if (nc == 4) {  // 가득 차면 가장 뒤(위쪽) 덩어리와 바꾼다
					slot = 0;
					for (int m = 1; m < 4; m++) {
						if (cand[m].z < cand[slot].z) {
							slot = m;
						}
					}
					if (cand[slot].z >= ctr.y) {
						slot = -1;
					}
				} else {
					nc++;
				}
				if (slot >= 0) {
					cand[slot] = vec4(u, ctr.y, d);
					cg[slot] = g;
					cb[slot] = acc / n;
					cc[slot] = ctr + off;
				}
			}
		}
		// 2) 앞 덩어리부터 잎을 찾는다 — 잎에 맞으면 잎 색, 잎 사이 틈이면 그 덩어리 속 그늘, 덩어리 밖이면 뒤 덩어리로
		bool done = false;
		float used = 0.0;  // 처리한 덩어리 비트
		for (int it = 0; it < 4; it++) {
			if (it >= nc || done) {
				break;
			}
			int m = -1;
			for (int q = 0; q < 4; q++) {
				if (q < nc && mod(floor(used / pow(2.0, float(q))), 2.0) < 0.5 && (m < 0 || cand[q].z > cand[m].z)) {
					m = q;
				}
			}
			used += pow(2.0, float(m));
			vec2 u = cand[m].xy;
			float rd = S * 0.5 * 0.82;
			float tk;
			float ed;
			vec4 lf = leaf_at(u, rd, cg[m], cc[m], t, gust_v, tk, ed);
			vec3 base = cb[m];
			if (lf.x > 0.5) {
				// 덩어리 공 음영을 잎 가운데에서 재서 잎 하나가 한 단(경계가 잎 모양으로 끊긴다)
				vec2 dv = lf.zw / rd;
				float dd = min(length(dv), 1.0);
				float nz = sqrt(max(0.0, 1.0 - dd * dd));
				float lit = dot(normalize(vec3(dv, nz)), normalize(vec3(-0.55, -0.75, 0.5)));
				float b = lit > 0.62 ? 4.0 : (lit > 0.3 ? 3.0 : (lit > 0.0 ? 2.0 : (lit > -0.35 ? 1.0 : 0.0)));
				b += tk > 0.93 ? 1.0 : (tk < 0.05 ? -1.0 : 0.0);  // 잎마다 조금씩 다르게
				// 돌풍이 지나가면 잎이 뒤집혀 밝은 뒷면이 보인다
				float flip = sin(t * 1.3 + lf.z * 0.35 - org_v.x * 2.0 + tk * 3.0);
				if (gust_v > 0.4 && flip > 0.8 && tk > 0.5) {
					b += 1.0;
				}
				b = clamp(b + ed, 0.0, 4.0);
				float f = b > 3.5 ? 1.2 : (b > 2.5 ? 1.0 : (b > 1.5 ? 0.8 : (b > 0.5 ? 0.6 : 0.42)));
				vec3 col = base * f;
				if (b > 3.5) {
					col *= vec3(1.1, 1.07, 0.82);  // 밝은 잎은 따뜻하게
				} else if (b < 1.5) {
					col *= vec3(0.8, 0.92, 1.14);  // 그늘 잎은 차갑게
				}
				c = vec4(col, 1.0);
				done = true;
			} else if (cand[m].w < 0.8 && all(greaterThan(p, vec2(6.0))) && all(lessThan(p, frame_rect.zw - 6.0))) {
				c = vec4(base * 0.46 * vec3(0.8, 0.92, 1.15), 1.0);  // 잎 사이 속 그늘
				done = true;
			}
		}
		if (!done && near && is_leaf(c)) {
			if (any(lessThan(p, vec2(12.0))) || any(greaterThan(p, frame_rect.zw - 12.0))) {
				c.a = 0.0;  // 판 가장자리에 남은 원래 잎 — 곧은 선으로 잘려 보이지 않게 지운다
			} else {
				c.rgb = c.rgb * 0.38 * vec3(0.8, 0.92, 1.15);  // 덩어리 사이 속 그늘
			}
		}
		// 3) 흩날리는 잎: 판마다 셋, 수관에서 떨어져 바람 따라 흔들리며 내려간다
		for (int k = 0; k < 3; k++) {
			float hk = hash(org_v * 3.7 + float(k) * 11.3);
			float T = 5.0 + hk * 3.0;
			float ph = fract(t / T + hk);
			vec2 st = vec2(frame_rect.z * (0.25 + 0.5 * hash(vec2(hk, floor(t / T + hk)))), frame_rect.w * 0.35);
			vec2 lp = st + vec2(sin(ph * 9.0 + hk * 6.0) * 7.0 + ph * 14.0, ph * frame_rect.w * 0.5);
			vec2 dd = floor(p * 0.5) - floor(lp * 0.5);
			bool tilt = sin(ph * 9.0 + hk * 6.0) > 0.0;
			if (ph < 0.92 && (dd == vec2(0.0) || dd == (tilt ? vec2(1.0, 0.0) : vec2(0.0, 1.0)))) {
				vec3 lc = nc > 0 ? cb[0] : vec3(0.35, 0.48, 0.18);
				c = vec4(lc * (tilt ? 1.15 : 0.8), 1.0);
			}
		}
	}
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a * COLOR.a;
}
