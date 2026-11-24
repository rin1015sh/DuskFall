extends "res://scripts/rules/effect_script.gd"
## 손에 무기를 불러낸다(불꽃 칼날·그늘 칼날, BG3 수치): 주문 동안 주무기를 불러낸 무기로 바꾸고, 끝나면 되돌린다.
## 무기 id와 상위 슬롯 주사위는 아래 표(무기 데이터 conjured: true — 상점·전리품에 나오지 않는다).
const U := preload("res://scripts/rules/spell_util.gd")

const WEAPONS := {
	"flame_blade": {"weapon": "conjured_flame_blade", "dice": {2: "3d6", 4: "4d6", 6: "5d6"}},  # 두 슬롯마다 +1d6
	"gloom_blade": {"weapon": "conjured_gloom_blade", "dice": {2: "2d8", 3: "3d8", 5: "4d8"}},  # 3·4레벨 3d8, 5·6레벨 4d8
}


func is_implemented() -> bool:
	return true


static func dice_for(spell_id: String, slot: int) -> String:
	var out := ""
	var table: Dictionary = WEAPONS[spell_id]["dice"]
	for lv: int in table:
		if slot >= lv:
			out = table[lv]
	return out


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var sid: String = ctx["spell"]["id"]
	var wid: String = WEAPONS[sid]["weapon"]
	var before: Dictionary = c.weapon_sets.duplicate(true)
	var sets: Dictionary = c.weapon_sets.duplicate(true)
	var cur: Dictionary = sets.get(c.active_set, {})
	cur["main"] = wid
	sets[c.active_set] = cur
	c.weapon_sets = sets
	c.set_meta("conjured_weapon_dice", dice_for(sid, int(ctx["slot"])))
	U.on_end(ctx, func() -> void:
		if is_instance_valid(c):
			c.weapon_sets = before
			c.remove_meta("conjured_weapon_dice"))
	ctx["instance"]["targets"].append(c)
	return {"ok": true, "weapon": wid}
