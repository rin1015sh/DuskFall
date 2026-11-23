extends RefCounted
## 클래스·종족·재주 기능 실행(상태 없음). 기능 데이터의 "script"를 scripts/rules/effects/<id>.gd로 돌린다.
## - hook(): 판정 엔진이 훅 시점에 부른다(on_hit, on_hp_zero, on_check_failed ...).
## - use(): 행동·보너스 행동으로 쓰는 기능(재기의 숨결 등). 비용과 자원을 확인·소모한다.
## - offer_reaction(): 반응형 기능이 반응 설정(매번 묻기·자동·끄기)을 따르게 한다.

static var _cache := {}


static func script_for(id: String) -> Object:
	if not _cache.has(id):
		var path := "res://scripts/rules/effects/%s.gd" % id
		_cache[id] = load(path) if ResourceLoader.exists(path) else null
	var s: Variant = _cache[id]
	return s.new() if s != null else null


static func run(script_id: String, ctx: Dictionary) -> Dictionary:
	var inst: Object = script_for(script_id)
	if inst == null or not inst.is_implemented():
		return {"ok": false, "reason": "미구현 기능 %s" % script_id}
	return inst.apply(ctx)


## 훅: 생물이 가진 기능 중 이 훅에 걸린 스크립트를 모두 돌린다. ctx에는 "self"가 들어간다.
static func hook(hook_name: String, creature: Node, ctx: Dictionary) -> void:
	if creature == null:
		return
	for sid: String in creature.feature_hooks.get(hook_name, []):
		var c := ctx.duplicate()
		c["self"] = creature
		c["res"] = ctx.get("res", ctx)
		run(sid, c)


## 행동형 기능 사용. 결과: {"ok", "reason", ...}
static func use(world: Dictionary, creature: Node, feature_id: String, target: Variant = null, opts: Dictionary = {}) -> Dictionary:
	var f: Dictionary = creature.feature_data.get(feature_id, {})
	if f.is_empty():
		return {"ok": false, "reason": "기능이 없다"}
	if not f.has("script"):
		return {"ok": false, "reason": "쓰는 기능이 아니다"}
	var cost: String = {"action": "action", "bonus_action": "bonus", "reaction": "reaction"}.get(f.get("kind", "free"), "free")
	var Combat := preload("res://scripts/rules/combat.gd")
	if not Combat.can_spend(creature, cost):
		return {"ok": false, "reason": "비용이 없다"}
	var res_id: String = f.get("resource", "")
	var pay_n := 1
	if res_id != "" and creature.resource(res_id) <= 0:
		# 대체 비용 alt_cost {resource, amount, cap}: 횟수가 없으면 다른 자원으로(마법의 화신 — 마법 점수 2로 타고난 마법)
		var alt: Dictionary = f.get("alt_cost", {})
		if alt.is_empty() or not creature.has_cap(str(alt.get("cap", ""))) or creature.resource(str(alt["resource"])) < int(alt.get("amount", 1)):
			return {"ok": false, "reason": "남은 횟수가 없다"}
		res_id = str(alt["resource"])
		pay_n = int(alt.get("amount", 1))
	var r := run(f["script"], {"world": world, "self": creature, "target": target, "opts": opts, "feature": f})
	if r.get("ok", false):
		Combat.spend(creature, cost)
		if res_id != "" and not r.get("keep_resource", false):
			for i in pay_n:
				creature.spend_resource(res_id)
	return r


## 반응형 기능: 지금 반응 대기열이 있으면 그 설정(묻기·자동·끄기)을 따르고, 없으면 자동.
static func offer_reaction(creature: Node, reaction_id: String, info: Dictionary, action: Callable, auto_yes: bool = true) -> bool:
	if not creature.can_react():
		return false
	var rq: Node = EventBus.reaction_queue
	if rq != null and is_instance_valid(rq):
		return rq.offer(creature, reaction_id, info, action, auto_yes)
	if creature.reaction_setting(reaction_id) == "off" or not auto_yes:
		return false
	action.call()
	return true
