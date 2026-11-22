extends "res://tests/test_case.gd"
## 룰북 9단계 예시 전투 2(3레벨, 숲 공터)의 환경 연쇄: 마른 풀 + 기름통 + Burning Hands.
## 기름통: 나무, 보통 크기 약한 물체 HP 4(SRD Object Hit Points), 내용물 기름 반경 1칸.

const Area := preload("res://scripts/rules/area.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")

const BARREL := {"id": "oil_barrel", "material": "wood", "hp": 4, "ac": 15, "weight_kg": 60.0,
	"contents": {"surface": "oil", "radius": 1}}


func _clearing() -> Array:
	var rows: Array = []
	for i in 9:
		rows.append("............")
	var g := make_grid(rows, "grass")
	return [g, make_surfaces(g)]


## 3. 위저드의 Burning Hands(원뿔 3칸, 민첩 DC 13, 3d6 화염)가 풀 위 고블린 둘을 덮는다.
func test_burning_hands_on_grass_goblins() -> void:
	var gs := _clearing()
	var g: Node = gs[0]
	var s: Node = gs[1]
	var wizard := make_creature({"is_player_character": true})
	var gob1 := make_creature({"hp_max": 10, "abilities": {"dex": 15}})
	var gob2 := make_creature({"hp_max": 10, "abilities": {"dex": 15}})
	g.place(wizard, Vector2i(1, 4))
	g.place(gob1, Vector2i(2, 4))
	g.place(gob2, Vector2i(3, 5))
	var cone := Area.cone(g, Vector2i(1, 4), Vector2i(1, 0), 3)
	var targets := Area.creatures_in(g, cone)
	assert_eq(targets.size(), 2)
	# 내성: gob1 실패(5 + 2), gob2 성공(14 + 2). 피해 3d6 한 번: 4 + 3 + 5 = 12
	Dice.force([5, 14, 4, 3, 5])
	Resolver.save_effect(targets, {"ability": "dex", "dc": 13},
		[{"type": "damage", "dice": "3d6", "damage_type": "fire"}],
		[{"type": "damage", "dice": "3d6", "damage_type": "fire", "scale": 0.5}])
	assert_true(gob1.dead, "실패 12 → 즉사")
	assert_eq(gob2.hp, 4, "성공 절반 6")
	s.tile_damage(cone, "fire", 12)
	for c in cone:
		assert_eq(g.surface_id(c), "fire", "원뿔이 덮은 풀 칸이 화염 표면 %s" % str(c))


## 풀 점화 → 기름통 파괴 → 기름 점화: 반응 깊이 3 안에서 끝난다(충돌 D).
func test_oil_barrel_chain_within_depth_3() -> void:
	var gs := _clearing()
	var g: Node = gs[0]
	var s: Node = gs[1]
	var barrel_cell := Vector2i(5, 4)
	g.place_object(barrel_cell, BARREL)
	var gob := make_creature({"hp_max": 10})
	g.place(gob, Vector2i(6, 4))
	# 원뿔이 통 바로 앞까지 태우고, 라운드 끝 번짐으로 통이 선 풀 칸에 불이 붙는다.
	var cone := Area.cone(g, Vector2i(1, 4), Vector2i(1, 0), 3)
	s.tile_damage(cone, "fire", 10)
	assert_false(barrel_cell in cone)
	assert_true(barrel_cell in s.preview_spread(), "다음 라운드에 통 칸으로 번진다")
	s.history.clear()
	Dice.force([4])  # 화염 표면 → 통 1d4 = 4 → HP 4 소진
	s.end_round()
	assert_true(g.object_at(barrel_cell).is_empty(), "기름통 파괴")
	var depths := {}
	for h in s.history:
		depths[h["reaction"]] = maxi(depths.get(h["reaction"], 0), h["depth"])
	assert_eq(depths.get("flammable_fire"), 1, "1: 풀 점화")
	assert_eq(depths.get("break:oil_barrel"), 2, "2: 통 파괴")
	assert_eq(depths.get("oil_onto_fire"), 3, "3: 불 위로 쏟아진 기름 점화")
	assert_eq(s.deferred.size(), 0, "상한 안에서 끝났다")
	assert_eq(g.surface_id(barrel_cell), "fire")
	assert_eq(g.surface_id(Vector2i(6, 4)), "oil", "불이 안 닿은 칸은 기름으로 남는다")
	# 기름은 가연성 표면이라 다음 라운드에 번진다 — 기름 위 고블린 칸 예고
	assert_true(Vector2i(6, 4) in s.preview_spread())
	assert_eq(s.spread_warnings([gob]), [gob])


## 4. 불이 풀을 따라 1칸씩 번져 2라운드 뒤 전사 칸에 닿는다. 미리보기가 그 전에 경고한다(충돌 C).
func test_spread_reaches_fighter_with_warning() -> void:
	var gs := _clearing()
	var g: Node = gs[0]
	var s: Node = gs[1]
	var fighter := make_creature({"is_player_character": true, "hp_max": 28})
	g.place(fighter, Vector2i(6, 4))
	s.tile_damage([Vector2i(4, 4)], "fire")
	assert_eq(s.spread_warnings([fighter]), [], "1라운드 뒤에는 아직")
	s.end_round()
	assert_eq(s.spread_warnings([fighter]), [fighter], "다음 라운드에 닿는다 → 경고")
	s.end_round()
	assert_eq(g.surface_id(Vector2i(6, 4)), "fire", "2라운드 뒤 전사 칸")
	s.creature_turn_start(fighter)
	assert_true(fighter.has_condition("burning"))
