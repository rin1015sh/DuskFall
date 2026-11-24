extends "res://scripts/rules/effect_script.gd"
## 무기 소마법(BG3식 — 우레 칼날·잉걸 칼날): 행동으로 주무기 근접 공격 하나(공격 행동이 아니라 추가 공격과 잇지 않는다).
## 맞히면 주문별 효과(rider)를 건다. 소마법 강화 5·10레벨.
const U := preload("res://scripts/rules/spell_util.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


static func tier(c: Node) -> int:
	return 2 if c.level >= 10 else (1 if c.level >= 5 else 0)


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Node = U.target(ctx)
	if t == null or t == c:
		return {"ok": false, "reason": "대상이 없다"}
	var wid: String = c.weapon("main")
	if wid == "" or Combat.is_ranged_weapon(Combat.weapon_data(wid)):
		wid = "unarmed" if wid == "" else wid
	var atk := Combat.build_weapon_attack(c, wid)
	if atk["kind"] != "melee":
		return {"ok": false, "reason": "근접 무기가 필요하다"}
	var res := Combat._do_attack(ctx["world"], c, t, atk)
	if res.get("hit", false) and not t.dead:
		rider(ctx, c, t)
	return {"ok": true, "hit": res.get("hit", false), "attack": res}


func rider(_ctx: Dictionary, _c: Node, _t: Node) -> void:
	pass
