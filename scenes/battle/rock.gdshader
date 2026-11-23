// 자연 바위 절벽 면(terrain_natural.gd): 키트 낭떠러지 암벽 그림(cliff_drops)을 세계 좌표로 입힌다 —
// 가로는 면을 따라 1칸 = 64px(4칸 묶음 반복), 세로는 높이 1단계 = 40px(160px 반복). 높이가 제각각인 면도 이음매 없이 이어진다.
// 정점 색 = 햇빛 음영 × 어둠. cutaway: 캐릭터 앞(남쪽)을 가리면 체크무늬로 비친다(terrain.gdshader와 같다).
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D tex : source_color, filter_nearest;
// 암벽 그림 묶음(px): x, y, 너비(256), 높이(160)
uniform vec4 frame = vec4(0.0, 0.0, 256.0, 160.0);
uniform vec2 atlas_px = vec2(1280.0, 160.0);
uniform bool cutaway = true;
uniform vec4 actors[24];
uniform int actor_count = 0;

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
	// 면 방향: 화면 미분으로 세계 법선을 구해 남북 면이면 x, 동서 면이면 z를 따라 감는다
	vec3 n = normalize(cross(dFdx(wpos), dFdy(wpos)));
	float along = abs(n.z) >= abs(n.x) ? wpos.x : wpos.z;
	// 단(160px)마다 가로로 어긋나게 깔아 반복이 덜 보이게
	float band = floor(wpos.y * 40.0 / (frame.w - 1.0));
	float u = frame.x + mod(along * 64.0 + band * 97.0, frame.z);
	float v = frame.y + frame.w - 0.5 - mod(wpos.y * 40.0, frame.w - 1.0);
	vec4 c = texture(tex, vec2(u, v) / atlas_px) * COLOR;
	// 바위 얼룩: 큰 얼룩 + 잔얼룩으로 밝기를 들쭉날쭉
	vec2 q = vec2(along, wpos.y);
	c.rgb *= mix(0.74, 1.08, vnoise(q * 0.8 + 5.0) * 0.7 + vnoise(q * 2.9) * 0.3);
	ALBEDO = c.rgb;
	if (cutaway) {
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
