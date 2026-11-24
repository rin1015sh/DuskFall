extends "res://tests/test_case.gd"
## 표면 시스템: 반응표 각 행, 표면 효과, 지속시간, 번짐, 연쇄 상한(룰북 4단계, 9단계 C·D).

const Area := preload("res://scripts/rules/area.gd")


func _setup(rows: Array = ["....."], material: String = "stone") -> Array:
	var g := make_grid(rows, material)
	return [g, make_surfaces(g)]


func _put(s: Node, c: Vector2i, id: String) -> void:
	s.place_surface([c], id)


# ---------- 반응표 ----------

func test_water_reactions() -> void:
	var gs := _setup()
	var g: Node = gs[0]
	var s: Node = gs[1]
	_put(s, Vector2i(0, 0), "water")
	_put(s, Vector2i(1, 0), "water")
	_put(s, Vector2i(2, 0), "water")
	s.tile_damage([Vector2i(0, 0)], "fire")
	assert_eq(g.surface_id(Vector2i(0, 0)), "", "물 + 화염 → 물 사라짐")
	assert_eq(g.cloud_id(Vector2i(0, 0)), "steam", "증기 구름")
	assert_eq(g.cloud(Vector2i(0, 0))["turns_left"], 3, "증기 3턴(changes.md)")
	s.tile_damage([Vector2i(1, 0)], "cold")
	assert_eq(g.surface_id(Vector2i(1, 0)), "ice")
	s.tile_damage([Vector2i(2, 0)], "lightning")
	assert_eq(g.surface_id(Vector2i(2, 0)), "electrified_water")


func test_ice_oil_blood_reactions() -> void:
	var gs := _setup()
	var g: Node = gs[0]
	var s: Node = gs[1]
	_put(s, Vector2i(0, 0), "ice")
	s.tile_damage([Vector2i(0, 0)], "fire")
	assert_eq(g.surface_id(Vector2i(0, 0)), "water", "얼음 + 화염 → 물")
	_put(s, Vector2i(1, 0), "oil")
	var gob := make_creature({"hp_max": 10})
	g.place(gob, Vector2i(1, 0))
	s.tile_damage([Vector2i(1, 0)], "fire")
	assert_eq(g.surface_id(Vector2i(1, 0)), "fire", "기름 + 화염 → 화염")
	assert_true(gob.has_condition("burning"), "위의 생물 연소")
	_put(s, Vector2i(2, 0), "blood")
	s.tile_damage([Vector2i(2, 0)], "fire")
	assert_eq(g.surface_id(Vector2i(2, 0)), "blood", "피는 불을 끈다")
	s.tile_damage([Vector2i(2, 0)], "cold")
	assert_eq(g.surface_id(Vector2i(2, 0)), "ice", "피 + 냉기 → 얼음")


func test_electrified_water_and_fire_reactions() -> void:
	var gs := _setup()
	var g: Node = gs[0]
	var s: Node = gs[1]
	_put(s, Vector2i(0, 0), "electrified_water")
	s.tile_damage([Vector2i(0, 0)], "fire")
	assert_eq(g.cloud_id(Vector2i(0, 0)), "steam")
	_put(s, Vector2i(1, 0), "electrified_water")
	s.tile_damage([Vector2i(1, 0)], "cold")
	assert_eq(g.surface_id(Vector2i(1, 0)), "ice")
	_put(s, Vector2i(2, 0), "fire")
	s.tile_damage([Vector2i(2, 0)], "cold")
	assert_eq(g.surface_id(Vector2i(2, 0)), "", "화염 + 냉기 → 소멸")
	_put(s, Vector2i(3, 0), "fire")
	s.apply_water([Vector2i(3, 0)])
	assert_eq(g.surface_id(Vector2i(3, 0)), "", "화염 + 물 → 소멸")
	assert_eq(g.cloud_id(Vector2i(3, 0)), "steam", "+ 증기")


func test_web_burns_into_fire_bg3() -> void:
	# BG3: 거미줄은 타서 보통 화염 표면이 된다(SRD 타는 거미줄 대신)
	var gs := _setup()
	var g: Node = gs[0]
	var s: Node = gs[1]
	_put(s, Vector2i(0, 0), "web")
	s.tile_damage([Vector2i(0, 0)], "fire")
	assert_eq(g.surface_id(Vector2i(0, 0)), "fire")


func test_flammable_material_ignites_and_burns_out() -> void:
	var gs := _setup(["..."], "grass")
	var g: Node = gs[0]
	var s: Node = gs[1]
	s.tile_damage([Vector2i(0, 0)], "fire")
	assert_eq(g.surface_id(Vector2i(0, 0)), "fire", "풀 + 화염 → 화염 표면")
	assert_eq(g.material(Vector2i(0, 0)), "burnt_ground", "탄 땅이 된다")
	s.tile_damage([Vector2i(2, 0)], "cold")
	assert_eq(g.surface_id(Vector2i(2, 0)), "", "가연성 재질 + 냉기는 반응 없음")


func test_wet_cell_does_not_ignite() -> void:
	var gs := _setup(["."], "grass")
	var g: Node = gs[0]
	var s: Node = gs[1]
	_put(s, Vector2i(0, 0), "water")
	s.tile_damage([Vector2i(0, 0)], "fire")
	assert_eq(g.surface_id(Vector2i(0, 0)), "", "물이 있으면 증기가 되고 불붙지 않는다")
	assert_eq(g.material(Vector2i(0, 0)), "grass")


func test_no_reaction_overwrites() -> void:
	var gs := _setup()
	var g: Node = gs[0]
	var s: Node = gs[1]
	_put(s, Vector2i(0, 0), "mud")
	_put(s, Vector2i(0, 0), "acid")
	assert_eq(g.surface_id(Vector2i(0, 0)), "acid", "반응이 없으면 덮어쓴다")
	_put(s, Vector2i(1, 0), "fire")
	_put(s, Vector2i(1, 0), "oil")
	assert_eq(g.surface_id(Vector2i(1, 0)), "fire", "기름이 불 위에 오면 점화")


func test_preview_reactions() -> void:
	var gs := _setup(["...."], "grass")
	var g: Node = gs[0]
	var s: Node = gs[1]
	_put(s, Vector2i(0, 0), "water")
	var p: Array = s.preview_tile_damage([Vector2i(0, 0), Vector2i(1, 0)], "fire")
	assert_eq(p.size(), 2)
	assert_eq(p[0]["reaction"], "water_fire")
	assert_eq(p[1]["reaction"], "flammable_fire")
	assert_eq(g.surface_id(Vector2i(1, 0)), "", "미리보기는 바꾸지 않는다")


# ---------- 생물에게 주는 효과 ----------

func test_enter_and_turn_start_once_per_turn() -> void:
	var gs := _setup(["....."])
	var g: Node = gs[0]
	var s: Node = gs[1]
	s.place_surface([Vector2i(1, 0), Vector2i(2, 0)], "poison")
	var cr := make_creature({"hp_max": 30})
	g.place(cr, Vector2i(0, 0))
	Dice.force([2])
	g.move_creature(cr, Vector2i(1, 0))
	assert_eq(cr.hp, 28, "들어갈 때 1d4 독")
	g.move_creature(cr, Vector2i(2, 0))
	assert_eq(cr.hp, 28, "같은 턴에 같은 표면 효과는 한 번만")
	Dice.force([3])
	s.creature_turn_start(cr)
	assert_eq(cr.hp, 25, "새 턴 시작에 다시")


func test_surface_save_dc() -> void:
	var gs := _setup(["..."])
	var g: Node = gs[0]
	var s: Node = gs[1]
	_put(s, Vector2i(1, 0), "ice")
	var cr := make_creature({"abilities": {"dex": 10}})
	g.place(cr, Vector2i(0, 0))
	Dice.force([11])
	g.move_creature(cr, Vector2i(1, 0))
	assert_true(cr.has_condition("prone"), "11 < DC 12 → 넘어짐")
	s.place_surface([Vector2i(2, 0)], "oil", {"dc": 15})
	var cr2 := make_creature({"abilities": {"dex": 10}})
	g.place(cr2, Vector2i(2, 0))
	Dice.force([13])
	s.creature_turn_start(cr2)
	assert_true(cr2.has_condition("prone"), "주문이 만든 표면은 시전자 DC(15)")


func test_water_wets_and_electrified_doubles() -> void:
	var gs := _setup(["..."])
	var g: Node = gs[0]
	var s: Node = gs[1]
	_put(s, Vector2i(1, 0), "electrified_water")
	var cr := make_creature({"hp_max": 30})
	g.place(cr, Vector2i(0, 0))
	Dice.force([3])
	g.move_creature(cr, Vector2i(1, 0))
	assert_true(cr.has_condition("wet"))
	assert_eq(cr.hp, 24, "젖음 취약으로 3 × 2")


func test_web_save_only_on_enter() -> void:
	var gs := _setup(["..."])
	var g: Node = gs[0]
	var s: Node = gs[1]
	_put(s, Vector2i(1, 0), "web")
	var cr := make_creature()
	g.place(cr, Vector2i(1, 0))
	s.creature_turn_start(cr)
	assert_eq(Dice.roll_log.size(), 0, "거미줄 내성은 들어갈 때만")
	g.move_creature(cr, Vector2i(0, 0))
	Dice.force([2])
	g.move_creature(cr, Vector2i(1, 0))
	assert_true(cr.has_condition("restrained"))


func test_thorns_damage_every_tile() -> void:
	var gs := _setup(["...."])
	var g: Node = gs[0]
	var s: Node = gs[1]
	s.place_surface([Vector2i(1, 0), Vector2i(2, 0)], "thorns")
	var cr := make_creature({"hp_max": 30})
	g.place(cr, Vector2i(0, 0))
	Dice.force([1, 1, 2, 2])
	g.move_creature(cr, Vector2i(1, 0))
	g.move_creature(cr, Vector2i(2, 0))
	assert_eq(cr.hp, 24, "1칸 이동마다 2d4")


# ---------- 시간 ----------

func test_durations_and_expiry() -> void:
	var gs := _setup(["...."])
	var g: Node = gs[0]
	var s: Node = gs[1]
	_put(s, Vector2i(0, 0), "acid")
	_put(s, Vector2i(1, 0), "ice")
	s.place_surface([Vector2i(2, 0)], "water", {"turns": -1})
	for i in 3:
		s.end_round()
	assert_eq(g.surface_id(Vector2i(0, 0)), "", "산 3턴")
	for i in 7:
		s.end_round()
	assert_eq(g.surface_id(Vector2i(1, 0)), "water", "얼음은 10턴 뒤 물")
	assert_eq(g.surface_id(Vector2i(2, 0)), "water", "맵 배치 물은 영구")


func test_fire_spreads_orthogonally_each_round() -> void:
	var gs := _setup(["....."], "grass")
	var g: Node = gs[0]
	var s: Node = gs[1]
	s.tile_damage([Vector2i(0, 0)], "fire")
	assert_eq(s.preview_spread(), [Vector2i(1, 0)], "번짐 예고")
	s.end_round()
	assert_eq(g.surface_id(Vector2i(1, 0)), "fire", "라운드 끝에 1칸")
	assert_eq(g.surface_id(Vector2i(2, 0)), "")
	s.end_round()
	assert_eq(g.surface_id(Vector2i(2, 0)), "fire")
	s.end_round()
	assert_eq(g.surface_id(Vector2i(0, 0)), "", "3턴 뒤 꺼짐")
	for i in 6:
		s.end_round()
	for c in g.all_cells():
		assert_eq(g.surface_id(c), "", "다 타고 나면 다시 붙지 않는다")


func test_fire_does_not_spread_diagonally_or_to_stone() -> void:
	var g := make_grid(["..", ".."], "stone")
	var s := make_surfaces(g)
	g.set_material(Vector2i(0, 0), "grass")
	g.set_material(Vector2i(1, 1), "grass")
	s.tile_damage([Vector2i(0, 0)], "fire")
	s.end_round()
	assert_eq(g.surface_id(Vector2i(1, 1)), "", "대각선으로는 번지지 않는다")


func test_spread_warning_for_allies() -> void:
	var gs := _setup(["...."], "grass")
	var g: Node = gs[0]
	var s: Node = gs[1]
	var fighter := make_creature()
	var wizard := make_creature()
	g.place(fighter, Vector2i(1, 0))
	g.place(wizard, Vector2i(3, 0))
	s.tile_damage([Vector2i(0, 0)], "fire")
	assert_eq(s.spread_warnings([fighter, wizard]), [fighter], "다음 라운드에 불이 닿는 아군 경고")


# ---------- 연쇄 상한 ----------

func test_cell_cap_defers_to_next_tick() -> void:
	var g := make_grid([".........", ".........", ".........", ".........", ".........",
		".........", ".........", ".........", "........."], "grass")
	var s := make_surfaces(g)
	var cells := Area.circle(g, Vector2i(4, 4), 4)
	assert_eq(cells.size(), 69)
	s.tile_damage(cells, "fire")
	var burning := 0
	for c in cells:
		if g.surface_id(c) == "fire":
			burning += 1
	assert_eq(burning, 64, "한 번에 64칸까지")
	assert_eq(s.deferred.size(), 5, "나머지는 미룬다")
	s.end_round()
	burning = 0
	for c in cells:
		if g.surface_id(c) == "fire" or g.material(c) == "burnt_ground":
			burning += 1
	assert_eq(burning, 69, "다음 턴 틱에 처리")


func test_depth_cap_defers() -> void:
	var gs := _setup(["....."])
	var g: Node = gs[0]
	var s: Node = gs[1]
	g.place_object(Vector2i(2, 0), {"id": "oil_barrel", "material": "wood", "hp": 4, "ac": 15,
		"contents": {"surface": "oil", "radius": 1}})
	# 깊이 3에서 통을 부수면 기름(깊이 4)은 미뤄진다.
	s._run([{"kind": "damage", "cell": Vector2i(2, 0), "damage_type": "bludgeoning", "amount": 10, "depth": 3}])
	assert_true(g.object_at(Vector2i(2, 0)).is_empty(), "깊이 3까지는 처리")
	assert_eq(g.surface_id(Vector2i(2, 0)), "", "깊이 4 기름은 아직")
	assert_eq(s.deferred.size(), 3)
	s.end_round()
	assert_eq(g.surface_id(Vector2i(2, 0)), "oil", "다음 턴 틱에 처리")


func test_objects_immune_to_poison_and_fragile_break() -> void:
	var gs := _setup(["..."])
	var g: Node = gs[0]
	var s: Node = gs[1]
	g.place_object(Vector2i(0, 0), {"id": "crate", "material": "wood", "hp": 18})
	s.tile_damage([Vector2i(0, 0)], "poison", 50)
	assert_false(g.object_at(Vector2i(0, 0)).is_empty(), "물체는 독 피해 면역")
	g.place_object(Vector2i(1, 0), {"id": "flask", "material": "glass", "hp": 2,
		"contents": {"surface": "acid", "radius": 0}})
	s.tile_damage([Vector2i(1, 0)], "bludgeoning", 1)
	assert_true(g.object_at(Vector2i(1, 0)).is_empty(), "깨짐 재질은 피해를 받으면 부서진다")
	assert_eq(g.surface_id(Vector2i(1, 0)), "acid", "내용물이 표면이 된다")
