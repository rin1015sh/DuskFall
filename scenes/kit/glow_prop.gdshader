shader_type spatial;
// 빛을 내는 물건(Kit3D.GLOWING — 모닥불·화로·횃불·초·등): 불꽃(밝고 채도 높은 화소)은 그대로 두고, 돌·쇠 같은 몸통은
// 어둡고 살짝 차갑게 눌러 둘레 그림(반실사 어두운 판타지 색)과 어울리게 한다. 깊이를 쓰지 않아 화면 외곽선이 붙지 않는다.
// 판 색(빛 단계 어둠) = 정점 색(Sprite3D modulate). 움직이는 판(AnimatedSprite3D)도 조각들이 한 시트라 UV 그대로 맞다.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D texture_albedo : source_color, filter_nearest;
uniform float body_dark = 0.72;

void fragment() {
	vec4 c = texture(texture_albedo, UV);
	float mx = max(max(c.r, c.g), c.b);
	float sat = mx - min(min(c.r, c.g), c.b);
	bool flame = (sat > 0.32 && mx > 0.55 && c.r >= c.b) || mx > 0.8;  // 불꽃 가운데 흰빛도 불꽃
	if (!flame && c.a > 0.5) {
		c.rgb *= body_dark * vec3(0.94, 0.97, 1.06);
	}
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a * COLOR.a;
}
