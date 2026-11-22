extends RefCounted
## 시험 전투 편성: 맵의 생물 배치로 세계를 만들고(WorldBuilder), 파티 그림(임시)을 붙인다.
## test_arena: 1레벨 파티 4명 + 고블린 전사 4(룰북 9단계 예시 전투 1의 구성). 그림은 임시(assets/actors).

const WorldBuilder := preload("res://scripts/rules/world_builder.gd")

## 파티 그림(임시): 클래스 → 걷기 시트
const PARTY_ART := {
	"fighter": "res://assets/actors/human.webp", "rogue": "res://assets/actors/barbarian.webp",
	"cleric": "res://assets/actors/dwarf.webp", "wizard": "res://assets/actors/elf.webp"}


## 결과: {"world", "party", "foes", "nodes"}. monster: test_arena의 goblin_* 자리에 놓을 몬스터.
static func build(map_id: String = "test_arena", level: int = 1, monster: String = "goblin_warrior") -> Dictionary:
	var opts := {"level": level}
	if map_id == "test_arena":
		opts["monster_for"] = func(sid: String, mid: String) -> String: return monster if sid.begins_with("goblin") else mid
	var b := WorldBuilder.build(map_id, opts)
	for c: Node in b["party"] + b["foes"]:
		add_art(c)
	return b


## 사람 캐릭터(파티·동료)에 클래스별 걷기 시트를 붙인다.
static func add_art(c: Node) -> void:
	if c.class_id != "" and not c.has_meta("art") or (c.class_id != "" and c.get_meta("art", {}).is_empty()):
		c.set_meta("art", {"sheet": PARTY_ART.get(c.class_id, "")})
