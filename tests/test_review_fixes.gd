extends "res://tests/test_case.gd"
## 2026-11-24 BG3 대조 검토에서 나온 버그 수정: 반복 내성·표면·던지기·돕기·밀치기·미리보기·AI.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Tactics := preload("res://scripts/ai/tactics.gd")
const AI := preload("res://scripts/ai/simple_ai.gd")
const Features := preload("res://scripts/rules/features.gd")


func _pc(cls: String, lv: int) -> Node:
	var r := Builder.build(Builder.default_spec(cls, lv))
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _surf(rows: Array = ["....."]) -> Array:
	var g := make_grid(rows)
	return [g, make_surfaces(g)]


func test_repeat_save_without_instance_removes_only_that_condition() -> void:
	var w := make_world(["...."])
	var c := make_creature({"team": "enemy", "hp_max": 30, "abilities": {"wis": 30}})
	w["grid"].place(c, Vector2i(0, 0))
	c.apply_condition("wet", 5)
	c.extra_modifiers.append({"effect": {"type": "modify", "stat": "ac", "add": 1}, "source": "equipment"})
	c.apply_condition("frightened", 5, null, {"repeat_save": {"ability": "wis", "dc": 5}})
	Dice.force([15])
	Spellcasting.on_turn_end(w, c)
	assert_false(c.has_condition("frightened"), "내성 성공 — 그 상태만 풀림")
	assert_true(c.has_condition("wet"), "다른 상태는 남는다")
	assert_eq(c.extra_modifiers.size(), 1, "장비 수정치도 남는다")


func test_hobbled_ends_and_web_restraint_escapable() -> void:
	assert_eq(int(RulesDB.get_entry("condition", "hobbled").get("default_duration_turns", -1)), 1)
	var gs := _surf()
	var g: Node = gs[0]
	var s: Node = gs[1]
	s.place_surface([Vector2i(1, 0)], "web", {"dc": 30})
	var c := make_creature({"hp_max": 20, "abilities": {"dex": 1}})
	g.place(c, Vector2i(1, 0))
	Dice.force([1])
	s.creature_entered(c, Vector2i(1, 0))
	assert_true(c.has_condition("restrained"))
	assert_true(c.condition_instance("restrained").get("params", {}).has("escape_dc"), "행동으로 빠져나올 수 있다")


func test_flammable_surfaces_burn_and_fire_onto_oil() -> void:
	var gs := _surf()
	var g: Node = gs[0]
	var s: Node = gs[1]
	s.place_surface([Vector2i(0, 0)], "vines")
	s.tile_damage([Vector2i(0, 0)], "fire")
	assert_eq(g.surface_id(Vector2i(0, 0)), "fire", "덩굴이 탄다")
	s.place_surface([Vector2i(2, 0)], "oil")
	s.place_surface([Vector2i(2, 0)], "fire")
	assert_eq(g.surface_id(Vector2i(2, 0)), "fire", "불을 기름 위에 놓아도 점화")
	s.place_surface([Vector2i(3, 0)], "water")
	s.place_surface([Vector2i(3, 0)], "fire")
	assert_eq(str(g.cloud(Vector2i(3, 0)).get("id", "")) if g.cloud(Vector2i(3, 0)) != null else "", "steam", "불 + 물 → 증기")


func test_map_water_returns_after_ice() -> void:
	var gs := _surf()
	var g: Node = gs[0]
	var s: Node = gs[1]
	g.set_surface(Vector2i(0, 0), {"id": "water", "turns_left": -1, "source": null, "dc": 12})
	s.tile_damage([Vector2i(0, 0)], "cold")
	assert_eq(g.surface_id(Vector2i(0, 0)), "ice")
	for i in 12:
		s.end_round()
	assert_eq(g.surface_id(Vector2i(0, 0)), "water", "얼음이 녹으면 맵 물로")
	assert_eq(int(g.surface(Vector2i(0, 0))["turns_left"]), -1, "다시 영구")


func test_large_creature_thorns_once_per_step() -> void:
	var gs := _surf(["......", "......"])
	var g: Node = gs[0]
	var s: Node = gs[1]
	s.place_surface([Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(3, 1)], "thorns")
	var big := make_creature({"hp_max": 100, "size": "large"})
	g.place(big, Vector2i(2, 0))
	var hp: int = big.hp
	Dice.force([2, 2])
	s.creature_entered(big, Vector2i(2, 0))
	assert_eq(big.hp, hp - 4, "2×2여도 2d4 한 번")


func test_stinking_cloud_on_enter() -> void:
	var gs := _surf()
	var g: Node = gs[0]
	var s: Node = gs[1]
	s._set_cloud(Vector2i(1, 0), "stinking_cloud", {"dc": 30})
	var c := make_creature({"hp_max": 20, "abilities": {"con": 1}})
	g.place(c, Vector2i(1, 0))
	Dice.force([1])
	s.creature_entered(c, Vector2i(1, 0))
	assert_true(c.has_condition("poisoned"), "들어오면 건강 내성")


func test_unarmed_adds_rage_and_throw_crit_doubles() -> void:
	var b := _pc("barbarian", 3)
	Features.use(make_world(["."]), b, "rage")
	var atk := Combat.build_weapon_attack(b, "unarmed")
	assert_eq(str(atk["damage"][0]["dice"]), str(1 + b.ability_mod("str") + Resolver.rage_bonus(b)), "비무장 1 + 근력 + 분노")
	var w := make_world(["....."])
	var f := _pc("fighter", 1)
	var g := make_creature({"team": "enemy", "hp_max": 50, "ac_base": 5, "weight_kg": 80.0})
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(2, 0))
	f.reset_turn()
	Dice.force([20, 3, 4])
	var r := Combat.throw_object(w, f, g, 20.0)
	assert_true(r["crit"])
	assert_eq(g.hp, 50 - 7, "치명타 — 1d4 두 번")


func test_help_wakes_sleeping_ally_and_neutral_shove_contested() -> void:
	var w := make_world([".....", ".....", ".....", ".....", ".....", ".....", "....."])
	var a := _pc("fighter", 1)
	var b := _pc("fighter", 1)
	w["grid"].place(a, Vector2i(0, 0))
	w["grid"].place(b, Vector2i(1, 0))
	b.apply_condition("asleep", 2)
	assert_true(b.has_condition("unconscious"))
	a.reset_turn()
	assert_true(Combat.help(w, a, b).get("ok", false))
	assert_false(b.has_condition("unconscious"), "돕기로 깨운다(BG3)")
	var n := make_creature({"team": "neutral", "hp_max": 20, "abilities": {"str": 30, "dex": 30}})
	w["grid"].place(n, Vector2i(0, 1))
	a.reset_turn()
	Dice.force([10, 10])
	var r := Combat.shove(w, a, n)
	assert_true(r.get("ok", false), str(r))
	assert_false(r.get("success", true), "중립은 판정을 한다(근력·민첩 30이면 버틴다)")


func test_preview_crit_threshold_and_spell_threat() -> void:
	var f := make_creature({"team": "party", "hp_max": 20})
	var e := make_creature({"team": "enemy", "hp_max": 20, "ac_base": 40})
	f.crit_threshold = 19
	var p := Resolver.preview_attack(f, e, {"name": "x", "bonus": 0, "kind": "melee", "weapon": true, "damage": [{"dice": "1d6", "damage_type": "slashing"}]})
	assert_near(float(p["hit_chance"]), 0.10, 0.001, "19~20 치명타는 늘 명중")
	var w := make_world(["....."])
	var wz := _pc("wizard", 3)
	var adj := make_creature({"team": "enemy", "hp_max": 40})
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(adj, Vector2i(1, 0))
	var sp := Resolver.preview_attack(wz, adj, {"name": "ray", "bonus": 5, "kind": "ranged", "weapon": false, "spell": true, "damage": [{"dice": "1d6", "damage_type": "fire"}]})
	assert_true("근접 위협" in sp.get("disadvantage", []), "주문 공격도 근접 위협 불리")


func test_ai_skips_charmer_and_avoids_fire() -> void:
	var w := make_world(["........", "........", "........"])
	var foe := make_creature({"team": "enemy", "hp_max": 20})
	var charmer := make_creature({"team": "party", "hp_max": 20})
	var other := make_creature({"team": "party", "hp_max": 20})
	w["grid"].place(foe, Vector2i(0, 1))
	w["grid"].place(charmer, Vector2i(1, 1))
	w["grid"].place(other, Vector2i(6, 1))
	foe.apply_condition("charmed", 5, charmer)
	assert_eq(Tactics.pick_target(w, foe), other, "매혹한 상대는 고르지 않는다")
	assert_true(Tactics.surface_danger("fire") > 0, "불은 위험(연소)")


func test_bg3_environment_rules() -> void:
	# 기름은 넘어뜨리지 않고(미끄러운 기름만), 얼린 얼음은 2턴, 어둠 안 실명·원거리 막힘
	assert_false(RulesDB.get_entry("surface", "oil").has("save"), "BG3 기름: 불만 붙는다")
	assert_true(RulesDB.get_entry("surface", "grease").has("save"), "미끄러운 기름: 넘어짐")
	var w := make_world(["......"])
	var s: Node = w["surfaces"]
	var g: Node = w["grid"]
	s.place_surface([Vector2i(0, 0)], "water")
	s.tile_damage([Vector2i(0, 0)], "cold")
	assert_eq(int(g.surface(Vector2i(0, 0))["turns_left"]), 2, "얼린 얼음 2턴")
	var a := make_creature({"team": "party", "hp_max": 20})
	var e := make_creature({"team": "enemy", "hp_max": 20})
	g.place(a, Vector2i(1, 0))
	g.place(e, Vector2i(5, 0))
	s._set_cloud(Vector2i(5, 0), "magical_darkness", {})
	var ctx := Combat.attack_context(w, a, e, Combat.build_weapon_attack(a, "shortbow"))
	assert_true(ctx.has("invalid"), "어둠 안으로 원거리 공격 불가")
	s.creature_turn_start(e)
	assert_true(e.has_condition("blinded"), "어둠 안이면 실명")


func test_bg3_jump_shove_fall_numbers() -> void:
	var c := make_creature({"abilities": {"str": 16}, "hp_max": 34})
	assert_eq(Combat.jump_distance(c), 5, "4.5m + 3m = 7.5m → 5칸")
	assert_eq(preload("res://scripts/rules/physics.gd").fall_damage(c, 2), 0, "3m 피해 없음")
	assert_eq(preload("res://scripts/rules/physics.gd").fall_damage(c, 4), 34 * 2 / 17 + 1, "6m")
	var t := make_creature({"abilities": {"str": 14, "dex": 10}, "skill_bonuses": {"athletics": 2}})
	assert_eq(Resolver.passive_skill(t, "str", "athletics"), 10 + 2 + 2, "수동 운동 10 + 근력 + 숙련")


func test_attack_any_creature_and_neutral_group_turns_hostile() -> void:
	var Actions := preload("res://scripts/rules/actions.gd")
	var w := make_world(["......", "......"])
	var f := _pc("fighter", 1)
	var ally := _pc("rogue", 1)
	var n1 := make_creature({"team": "neutral", "hp_max": 30, "ac_base": 5})
	var n2 := make_creature({"team": "neutral", "hp_max": 30})
	var other := make_creature({"team": "neutral", "hp_max": 30})
	n1.faction = "villagers"
	n2.faction = "villagers"
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(1, 0))
	w["grid"].place(n1, Vector2i(0, 1))
	w["grid"].place(n2, Vector2i(4, 1))
	w["grid"].place(other, Vector2i(5, 0))
	f.reset_turn()
	var pv: Dictionary = Actions.preview(w, f, "attack", Vector2i(1, 0))
	assert_true(pv.get("valid", false), "BG3: 아군도 노릴 수 있다")
	assert_eq(str(pv.get("warning", "")), "아군을 공격한다", "붉은 경고")
	Dice.force([18, 3])
	assert_true(Actions.execute(w, f, "attack", Vector2i(1, 0)).get("ok", false))
	assert_true(ally.hp < ally.hp_max, "아군이 맞는다")
	assert_eq(ally.team, "party", "아군은 편이 바뀌지 않는다")
	f.reset_turn()
	Dice.force([18, 3])
	Actions.execute(w, f, "attack", Vector2i(0, 1))
	assert_eq(n1.team, "enemy", "중립을 공격하면 적대")
	assert_eq(n2.team, "enemy", "같은 세력 전원 적대")
	assert_eq(other.team, "neutral", "다른 중립은 그대로")
