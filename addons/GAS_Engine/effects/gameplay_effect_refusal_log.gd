## A fixed-capacity ring buffer of recent GameplayEffect refusals, for the
## runtime debugger alone - never gameplay authority. `enabled = false` costs
## nothing and changes nothing else about how effects apply or refuse;
## `enabled = true` costs one append per refusal.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayEffectRefusalLog extends RefCounted

const DEFAULT_CAPACITY: int = 32

var enabled: bool = true
var capacity: int = DEFAULT_CAPACITY:
	set(value):
		capacity = maxi(value, 0)
		_trim_to_capacity()

var _records: Array[GameplayEffectRefusalRecord] = []
var _next_order: int = 0


func record(result: GameplayEffectApplicationResult) -> void:
	if not enabled or result == null:
		return
	var entry: GameplayEffectRefusalRecord = GameplayEffectRefusalRecord.new()
	entry.result = result
	entry.order = _next_order
	_next_order += 1
	_records.append(entry)
	_trim_to_capacity()


func _trim_to_capacity() -> void:
	while _records.size() > capacity:
		_records.remove_at(0)


## Oldest first, as a copy - a caller iterating while a new refusal lands must
## not see the live array shift under it.
func recent() -> Array[GameplayEffectRefusalRecord]:
	return _records.duplicate()


func clear() -> void:
	_records.clear()
