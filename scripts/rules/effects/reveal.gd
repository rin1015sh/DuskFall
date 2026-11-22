extends "res://scripts/rules/effect_script.gd"
## 감지 주문(Detect Magic·Evil and Good·Poison and Disease, Find Traps, Locate Object): Find Traps는 24칸·시야선 안 함정 위치를 드러내고, Detect Magic은 6칸 안 마법 함정(룬)을, Detect Evil and Good은 6칸 안 해당 종류 생물의 숨음·투명을 드러낸다. 나머지는 기록만.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var g := U.grid(ctx)
	var c: Node = ctx["self"]
	var sid: String = ctx["spell"]["id"]
	var o: Vector2i = g.cell_of(c)
	var found := 0
	match sid:
		"find_traps", "detect_magic":
			var reach := 24 if sid == "find_traps" else 6
			for t: Dictionary in ctx["world"].get("traps", []):
				var tc := Vector2i(int(t["cell"][0]), int(t["cell"][1]))
				if t["state"] == "armed" and g.distance(o, tc) <= reach and g.has_line_of_sight(o, tc):
					if sid == "detect_magic" and not str(t.get("id", "")).contains("glyph"):
						continue
					t["found"] = true
					found += 1
		"detect_evil_and_good":
			for t: Node in g.creatures():
				if t.creature_type in ["aberration", "celestial", "elemental", "fey", "fiend", "undead"] and g.distance_between(c, t) <= 6:
					t.remove_condition("invisible")
					found += 1
	Dice.log_text("%s: %d개를 감지했다" % [ctx["spell"]["name"]["en"], found])
	return {"ok": true, "found": found}
