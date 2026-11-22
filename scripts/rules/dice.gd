extends Node
## 주사위(오토로드). 룰북 8단계 'Godot 구조'.
## 시드를 고정한 난수를 쓰고 모든 굴림을 로그로 남긴다.
## 0단계: 빈 골격. 굴림·로그는 1단계에서 구현한다.

var _rng := RandomNumberGenerator.new()
## 굴림 기록. 항목 모양은 1단계에서 정한다.
var roll_log: Array[Dictionary] = []


## 시드를 정하고 로그를 비운다.
func set_seed(value: int) -> void:
	_rng.seed = value
	roll_log.clear()
