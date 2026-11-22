extends Node
## 반응 창. 룰북 3단계 '반응 주문·기능', 8단계 우선순위 규칙 4.
## 반응마다 설정(매번 묻기 ask / 자동 auto / 끄기 off)을 따른다.
## 묻기는 ask_callback(생물, 반응 ID, 정보) -> bool 로 답을 받는다(화면은 4단계). 콜백이 없으면 자동과 같다.
## 자동은 결과가 바뀔 때만 쓴다(예: Shield는 명중이 빗나감으로 바뀔 때만).

const Resolver := preload("res://scripts/rules/resolver.gd")

var world: Dictionary = {}
var ask_callback: Callable
## 기록: {"creature", "reaction", "used", "mode"}
var history: Array[Dictionary] = []


func setup(w: Dictionary) -> Node:
	world = w
	world["reactions"] = self
	EventBus.reaction_queue = self
	if not EventBus.on_after_attack_roll.is_connected(_on_after_attack_roll):
		EventBus.on_after_attack_roll.connect(_on_after_attack_roll)
	return self


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if EventBus.on_after_attack_roll.is_connected(_on_after_attack_roll):
			EventBus.on_after_attack_roll.disconnect(_on_after_attack_roll)
		if EventBus.reaction_queue == self:
			EventBus.reaction_queue = null


## 반응 창 하나. 쓰기로 하면 action을 실행한다. 쓴 경우 true.
func offer(c: Node, reaction_id: String, info: Dictionary, action: Callable, auto_yes: bool = true) -> bool:
	if not c.known_reactions.has(reaction_id) or not c.can_react():
		return false
	var setting: String = c.reaction_setting(reaction_id)
	var use := false
	match setting:
		"off":
			use = false
		"auto":
			use = auto_yes
		"ask":
			use = ask_callback.call(c, reaction_id, info) if ask_callback.is_valid() else auto_yes
	history.append({"creature": c, "reaction": reaction_id, "used": use, "mode": setting})
	if use:
		action.call()
	return use


# ---------- Shield(SRD 5.2.1: 반응, AC +5, 다음 자기 턴 시작까지, 1레벨 슬롯) ----------

func _on_after_attack_roll(res: Dictionary) -> void:
	if res.get("preview", false) or not res.get("hit", false) or res.get("crit", false):
		return
	var t: Node = res["target"]
	if not t.known_reactions.has("shield"):
		return
	var slot := lowest_slot(t, 1)
	if slot == "":
		return
	var would_miss: bool = res["total"] < res["ac"] + res["ac_bonus"] + 5
	offer(t, "shield", {"attack": res, "would_miss": would_miss}, func() -> void:
		t.spend_resource(slot)
		t.turn["reaction"] = int(t.turn.get("reaction", 1)) - 1
		res["ac_bonus"] += 5
		t.extra_modifiers.append({"effect": {"type": "modify", "stat": "ac", "add": 5}, "source": "shield",
			"until_turn_start_of": t})
		Dice.log_text("%s Shield: AC +5" % t.label()), would_miss)


## min_level 이상에서 가장 낮은 남은 주문 슬롯 자원 ID. 없으면 "".
static func lowest_slot(c: Node, min_level: int) -> String:
	for lv in range(min_level, 10):
		var id := "spell_slot_%d" % lv
		if c.resource(id) > 0:
			return id
	return ""
