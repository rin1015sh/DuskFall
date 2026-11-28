shader_type spatial;
// 드리운 그림자(Kit3D.add_cast_shadow): 서 있는 그림의 실루엣을 바닥에 눕혀 해 반대쪽(남동)으로 늘인 판.
// 그림 알파 반 넘는 곳만 한 색 그늘(반투명 바닥 그림자 자국은 빼서 겹치지 않게), 그림 도트 격자에 맞춰 찾는다.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform sampler2D texture_albedo : source_color, filter_nearest;
uniform float strength = 0.3;
uniform float length_k = 1.0;  // (안 씀 — 길이는 판 자세로)
uniform vec3 tint = vec3(0.06, 0.07, 0.12);

void fragment() {
	float a = texture(texture_albedo, UV).a;
	ALBEDO = tint;
	ALPHA = a > 0.5 ? strength : 0.0;
}
