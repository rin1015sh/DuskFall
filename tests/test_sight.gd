extends "res://tests/test_case.gd"
## 시야·빛·가려짐·고지(룰북 4단계 빛·높은 곳, changes.md 시야, SRD Obscured·Unseen Attackers).

const Resolver := preload("res://scripts/rules/resolver.gd")


func test_line_of_sight_walls() -> void:
	var g := make_grid([
		".....",
		"..#..",
		".....",
	])
	assert_false(g.has_line_of_sight(Vector2i(0, 1), Vector2i(4, 1)), "벽이 막는다")
	assert_true(g.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0)))
	assert_true(g.has_line_of_sight(Vector2i(1, 0), Vector2i(3, 2)) == false, "벽 칸을 지나는 대각선은 막힌다")
	assert_true(g.has_line_of_sight(Vector2i(1, 0), Vector2i(3, 0)) and g.has_line_of_sight(Vector2i(2, 0), Vector2i(3, 1)), "모서리를 스치면 한쪽만 벽이면 보인다")


func test_height_does_not_block_sight() -> void:
	var g := make_grid(["0550"])
	assert_true(g.has_line_of_sight(Vector2i(0, 0), Vector2i(3, 0)))


func test_fog_cloud_blocks_sight() -> void:
	var g := make_grid(["....."])
	g.set_cloud(Vector2i(2, 0), {"id": "fog", "turns_left": -1, "source": null, "dc": 12})
	assert_false(g.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0)))
	assert_true(g.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0), true), "범위 판정은 벽만 본다")


func test_torch_light() -> void:
	var g := make_grid(["..........."])
	for c in g.all_cells():
		g.set_base_light(c, GridWorldScript.Light.DARK)
	# 횃불: 반경 4칸 밝음 + 4칸 어스름
	g.light_sources.append({"id": "torch", "cell": Vector2i(0, 0), "bright": 4, "dim": 4})
	assert_eq(g.light_at(Vector2i(4, 0)), GridWorldScript.Light.BRIGHT)
	assert_eq(g.light_at(Vector2i(5, 0)), GridWorldScript.Light.DIM)
	assert_eq(g.light_at(Vector2i(8, 0)), GridWorldScript.Light.DIM)
	assert_eq(g.light_at(Vector2i(9, 0)), GridWorldScript.Light.DARK)


func test_darkvision_and_magical_darkness() -> void:
	var g := make_grid(["......"])
	for c in g.all_cells():
		g.set_base_light(c, GridWorldScript.Light.DARK)
	var human := make_creature()
	var dwarf := make_creature({"senses": ["darkvision"]})
	g.place(human, Vector2i(0, 0))
	g.place(dwarf, Vector2i(1, 0))
	assert_eq(g.obscurity_for(human, Vector2i(5, 0)), 2, "어둠은 심하게 가려짐")
	assert_eq(g.obscurity_for(dwarf, Vector2i(5, 0)), 1, "암시야: 어둠을 어스름처럼")
	g.set_cloud(Vector2i(5, 0), {"id": "magical_darkness", "turns_left": -1, "source": null, "dc": 12})
	assert_eq(g.obscurity_for(dwarf, Vector2i(5, 0)), 2, "마법 어둠은 암시야로도 못 본다")


func test_unseen_target_and_attacker() -> void:
	var g := make_grid(["......"])
	for c in g.all_cells():
		g.set_base_light(c, GridWorldScript.Light.DARK)
	var human := make_creature()
	var goblin := make_creature({"senses": ["darkvision"]})
	g.place(human, Vector2i(0, 0))
	g.place(goblin, Vector2i(4, 0))
	var ctx: Dictionary = g.attack_context(human, goblin)
	assert_eq(ctx["disadvantage"].size(), 1, "볼 수 없는 대상 공격은 불리")
	ctx = g.attack_context(goblin, human)
	assert_eq(Resolver.mode_of(ctx["advantage"], ctx["disadvantage"]), 1, "대상이 못 보는 공격자는 유리")


func test_high_ground_context_and_range() -> void:
	var g := make_grid(["3000000"])
	var archer := make_creature()
	var target := make_creature()
	g.place(archer, Vector2i(0, 0))
	g.place(target, Vector2i(6, 0))
	var ctx: Dictionary = g.attack_context(archer, target)
	assert_eq(ctx["height_diff"], 3)
	assert_eq(ctx["distance_tiles"], 6)
	assert_eq(g.effective_range(archer, Vector2i(6, 0), 4), 7, "낮은 대상에게 단계당 +1칸")
	assert_false(g.in_range(archer, target, 2))
	assert_true(g.in_range(archer, target, 3))
	var atk := {"bonus": 4, "damage": [{"dice": "1d6", "damage_type": "piercing"}]}
	assert_eq(Resolver.preview_attack(archer, target, atk, ctx)["attack_bonus"], 6, "고지 +2")


func test_frightened_regardless_of_sight_bg3() -> void:
	var g := make_grid([".#."])
	var scared := make_creature()
	var ghost := make_creature()
	var foe := make_creature()
	g.place(scared, Vector2i(0, 0))
	g.place(ghost, Vector2i(2, 0))
	g.place(foe, Vector2i(0, 0))
	scared.apply_condition("frightened", 10, ghost)
	var ctx: Dictionary = g.attack_context(scared, foe)
	assert_false(ctx["source_in_sight"], "벽 뒤의 원인은 보이지 않는다")
	var atk := {"bonus": 0, "damage": []}
	assert_eq(Resolver.preview_attack(scared, foe, atk, ctx)["mode"], -1, "BG3: 원인이 안 보여도 불리")
	assert_eq(scared.speed(), 0, "BG3: 공포 — 움직일 수 없다")
	assert_eq(Resolver.preview_attack(scared, foe, atk, {})["mode"], -1)
