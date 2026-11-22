extends RefCounted
## 주사위 식 계산(상태 없음). "2d6+3", "1d4+1", "-1d4", "5" 같은 식을 읽고
## 굴리지 않고 최솟값·최댓값·평균을 낸다. 굴림은 Dice 오토로드가 한다.

const _TERM := "([+-]?)(?:(\\d+)d(\\d+)|(\\d+))"


## 식을 읽는다. 실패하면 빈 Dictionary.
## 결과: {"dice": [{"count", "sides", "sign"}], "flat": int}
static func parse(expr: String) -> Dictionary:
	var s := expr.strip_edges()
	if s == "":
		return {}
	var re := RegEx.create_from_string(_TERM)
	var pos := 0
	var out := {"dice": [], "flat": 0}
	for m in re.search_all(s):
		if m.get_start() != pos:
			return {}
		if pos > 0 and m.get_string(1) == "":
			return {}  # 두 번째 항부터는 +/- 가 있어야 한다.
		var sign := -1 if m.get_string(1) == "-" else 1
		if m.get_string(2) != "":
			var count := m.get_string(2).to_int()
			var sides := m.get_string(3).to_int()
			if count <= 0 or sides <= 0:
				return {}
			out["dice"].append({"count": count, "sides": sides, "sign": sign})
		else:
			out["flat"] += sign * m.get_string(4).to_int()
		pos = m.get_end()
	if pos != s.length():
		return {}
	return out


## 굴리지 않은 통계. crit이면 주사위 개수 2배(수정치는 그대로).
static func stats(expr: String, crit: bool = false) -> Dictionary:
	var p := parse(expr)
	if p.is_empty():
		return {}
	var lo: float = p["flat"]
	var hi: float = p["flat"]
	var avg: float = p["flat"]
	for d: Dictionary in p["dice"]:
		var n: int = d["count"] * (2 if crit else 1)
		var a: float = n
		var b: float = n * d["sides"]
		if d["sign"] < 0:
			lo -= b
			hi -= a
			avg -= n * (d["sides"] + 1) / 2.0
		else:
			lo += a
			hi += b
			avg += n * (d["sides"] + 1) / 2.0
	return {"min": lo, "max": hi, "avg": avg}
