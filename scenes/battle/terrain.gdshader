// 지형(바닥·벽·절벽) 그림: 빛 없음(그림에 그려져 있다), 정점 색 = 음영·어둠.
// cutaway: 캐릭터 앞(남쪽)을 가리는 벽·절벽은 그 캐릭터가 보이게 체크무늬로 반쯤 지운다(옛 2D 반투명 대신).
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D tex : source_color, filter_nearest;
uniform bool cutaway = false;
uniform vec4 actors[24];
uniform int actor_count = 0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 c = texture(tex, UV) * COLOR;
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
