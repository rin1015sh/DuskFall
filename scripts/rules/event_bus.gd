extends Node
## 훅 시그널 중계(오토로드). 룰북 8단계 '이벤트 훅' 표.
## 데이터의 "hook" 필드는 아래 시그널 이름을 그대로 쓴다.
## 0단계: 시그널 선언만 있다. 인자 모양은 1단계 이후 판정 엔진과 함께 다듬는다.

## 지금 전투의 반응 대기열(ReactionQueue). 기능 스크립트가 반응 설정(매번 묻기·자동·끄기)을 따르려고 쓴다.
## 실시간 탐험 중인가(전투 밖). 탐험 노드가 켜고 전투가 끄고 켠다.
## 실시간에는 반응이 발동하지 않고(5단계), 쓰러지면 사망 내성 없이 안정 상태(7단계 결정 2).
var realtime := false
var reaction_queue: Node = null

## 전투 구역 진입, 적대 행동
signal on_combat_start()
## 라운드 시작(탐험 중에는 6초 틱)
signal on_round_start()
## 라운드 끝(탐험 중에는 6초 틱)
signal on_round_end()
## 생물의 턴 시작
signal on_turn_start(creature: Object)
## 생물의 턴 끝
signal on_turn_end(creature: Object)
## 이동·강제 이동으로 칸에 들어감
signal on_enter_tile(creature: Object, cell: Vector2i)
## 이동·강제 이동으로 칸을 떠남
signal on_leave_tile(creature: Object, cell: Vector2i)
## 공격 굴림 직전
signal on_before_attack_roll(ctx: Dictionary)
## 굴림 뒤 명중 확정 전
signal on_after_attack_roll(ctx: Dictionary)
## 명중 확정
signal on_hit(ctx: Dictionary)
## 빗나감 확정
signal on_miss(ctx: Dictionary)
## 치명타 확정
signal on_crit(ctx: Dictionary)
## 피해 적용 직후
signal on_damage_taken(ctx: Dictionary)
## HP가 0이 될 때
signal on_hp_zero(ctx: Dictionary)
## 회복될 때
signal on_heal(ctx: Dictionary)
## 내성 굴림 전후
signal on_save(ctx: Dictionary)
## 능력 판정 실패 직후
signal on_check_failed(ctx: Dictionary)
## 시전 시작
signal on_spell_cast(ctx: Dictionary)
## 상태가 붙음
signal on_condition_applied(creature: Object, condition_id: String)
## 상태가 풀림
signal on_condition_removed(creature: Object, condition_id: String)
## 칸이 피해 유형을 받을 때
signal on_tile_damage_type(cell: Vector2i, damage_type: String)
## 낙하 시작, 피해 굴림 전(changes.md 2026-11-22). ctx["prevented"] = true로 피해를 막는다.
signal on_fall(ctx: Dictionary)
## 숨긴 물체·함정의 반경에 들어갈 때
signal on_detect_radius(creature: Object, target: Object)
## NPC 시야 원뿔 안에서 절도가 일어날 때
signal on_witness(witness: Object, thief: Object)
## 상태를 건 생물이 그 상태의 대상을 맞혔다(상태 hooks.on_hit_by_source — 사냥꾼의 표식)
signal on_hit_by_source(ctx: Dictionary)
## 무기로 맞혔다(공격자 상태 hooks.on_weapon_hit — 얽어매는 일격)
signal on_weapon_hit(ctx: Dictionary)
## 짧은 휴식
signal on_short_rest()
## 긴 휴식
signal on_long_rest()


## 훅 이름 목록(데이터 검증에서 쓴다).
func hook_names() -> PackedStringArray:
	return PackedStringArray([
		"on_combat_start",
		"on_round_start",
		"on_round_end",
		"on_turn_start",
		"on_turn_end",
		"on_enter_tile",
		"on_leave_tile",
		"on_before_attack_roll",
		"on_after_attack_roll",
		"on_hit",
		"on_miss",
		"on_crit",
		"on_damage_taken",
		"on_hp_zero",
		"on_heal",
		"on_save",
		"on_check_failed",
		"on_spell_cast",
		"on_condition_applied",
		"on_condition_removed",
		"on_tile_damage_type",
		"on_fall",
		"on_detect_radius",
		"on_witness",
		"on_short_rest",
		"on_long_rest",
		# 상태 훅(resolver._hit_riders — 신호 없이 명중 처리 중에 데이터를 읽는다)
		"on_hit_by_source",  # 이 상태를 건 생물이 지닌 생물을 공격으로 맞힐 때(사냥꾼의 표식)
		"on_weapon_hit",  # 이 상태를 지닌 생물이 무기로 맞힐 때(얽어매는 일격)
	])
