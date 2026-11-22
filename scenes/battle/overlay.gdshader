// 바닥 위에 까는 표면 그림(물·얼음·진흙): 반투명. 칸 데이터 텍스처로 칸마다 표면을 찾는다.
// 가장자리는 위치를 잡음으로 흔들어(floor.gdshader와 같은 흔들림) 웅덩이처럼 들쭉날쭉하게 — 표면 칸과 그 이웃 칸에 네모를 깔고
// 흔든 위치의 칸에 표면이 없으면 지운다. 높이가 다른 칸으로는 번지지 않는다.
// 정점 색 = 어둠, 색조·불투명도는 표면별 팔레트(tints).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D tex : source_color, filter_nearest;
// 칸마다 RGBA8: r,g = 표면 그림 묶음의 첫 조각, b = 팔레트 번호 + 1(0 = 표면 없음)
uniform sampler2D surf : filter_nearest;
// 칸마다 RG8: r = 높이, g = 바닥 있음(1)
uniform sampler2D info : filter_nearest;
uniform ivec2 map_size = ivec2(1, 1);
uniform vec2 atlas_px = vec2(2048.0, 3328.0);
uniform float tile_px = 64.0;
uniform float warp = 0.36;
uniform vec4 tints[8];

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
	vec2 p = wpos.xz;
	ivec2 c0 = clamp(ivec2(floor(p)), ivec2(0), map_size - 1);
	vec2 w = vec2(vnoise(p * 1.3 + 11.0), vnoise(p * 1.3 + 47.0)) * 0.7
		+ vec2(vnoise(p * 4.1 + 3.0), vnoise(p * 4.1 + 29.0)) * 0.3 - 0.5;
	ivec2 c = ivec2(floor(p + w * 2.0 * warp));
	if (any(lessThan(c, ivec2(0))) || any(greaterThanEqual(c, map_size))) {
		c = c0;
	}
	ivec4 s = ivec4(round(texelFetch(surf, c, 0) * 255.0));
	vec2 ic = round(texelFetch(info, c, 0).rg * 255.0);
	vec2 i0 = round(texelFetch(info, c0, 0).rg * 255.0);
	if (s.b == 0 || ic.g < 0.5 || ic.r != i0.r) {
		discard;
	}
	ivec2 pc = ivec2(floor(p));
	ivec2 tile = s.rg + ((pc % 4) + 4) % 4;
	vec4 col = texture(tex, (vec2(tile) + clamp(fract(p), 0.004, 0.996)) * tile_px / atlas_px) * tints[s.b - 1];
	ALBEDO = col.rgb * COLOR.rgb;
	ALPHA = col.a;
}
