shader_type spatial;
// 바람에 흔들리는 서 있는 그림 판(풀 덤불·꽃·나무 — kit3d.gd가 붙인다).
// 판 위쪽 두 꼭짓점만 옆으로 밀어 밑동은 땅에 붙은 채 기운다. 세기는 판 위 끝에서 amp 도트.
// 흔들림 = 자리마다 다른 잔물결 + 맵을 가로질러 천천히 지나가는 돌풍(바람은 서쪽에서 동쪽).
// 깊이: 불투명 부분은 미리 깊이를 써서(외곽선·가림이 원래 판과 같다), 반투명 그림자 부분은 섞어 그린다.
// 판 색(빛 단계 어둠) = 정점 색(Sprite3D modulate).
render_mode unshaded, cull_disabled, depth_prepass_alpha, blend_mix;

uniform sampler2D texture_albedo : source_color, filter_nearest;
// 판 위 끝 흔들림(판 안 좌표 단위 — kit3d가 도트 → 판 단위로 바꿔 넣는다)
uniform float amp = 0.03;
uniform float speed = 1.0;
// 잎 반짝임(나무·덤불): 초록 화소 위로 돌풍 물결이 지나갈 때 도트 단위로 밝아졌다 어두워진다(잎이 뒤집히는 느낌)
uniform float leaf = 0.0;

varying vec3 wpos;

void vertex() {
	vec2 o = MODEL_MATRIX[3].xz;
	float t = TIME * speed;
	float ripple = sin(t * 1.9 + o.x * 1.3 + o.y * 0.7) * 0.55 + sin(t * 3.1 + o.y * 1.9) * 0.25;
	float gust = smoothstep(-0.3, 1.0, sin(t * 0.55 - o.x * 0.32 - o.y * 0.12));
	float top = step(0.0, VERTEX.y);
	VERTEX.x += top * amp * (ripple * (0.45 + 0.55 * gust) + gust * 0.6);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	vec4 c = texture(texture_albedo, UV);
	if (leaf > 0.0 && c.g > c.r * 1.05 && c.g > c.b * 1.1) {
		vec2 d = floor(vec2(wpos.x, wpos.y) * 32.0);  // 도트 격자
		float wave = sin(wpos.x * 2.2 + wpos.y * 1.3 - TIME * speed * 1.6 + hash(floor(d / 3.0)) * 2.0);
		float h = hash(d);
		if (wave > 0.55 && h > 0.55) {
			c.rgb *= 1.0 + 0.18 * leaf;
		} else if (wave < -0.7 && h > 0.7) {
			c.rgb *= 1.0 - 0.12 * leaf;
		}
	}
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a * COLOR.a;
}
