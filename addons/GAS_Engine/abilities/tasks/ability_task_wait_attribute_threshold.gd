## Wait for one attribute to cross a threshold, by whichever comparison the
## caller names.
##
## No per-frame polling: this reacts to `attribute_changed` the same way
## AbilityTaskWaitAttributeChange does, and re-tests the comparison only when
## the attribute actually moved.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name AbilityTaskWaitAttributeThreshold extends GameplayAbilityTask

enum Comparison {
	LESS,
	LESS_OR_EQUAL,
	GREATER,
	GREATER_OR_EQUAL,
	EQUAL_APPROX,
}

var target_asc: AbilitySystemComponent = null
var attribute_name: StringName = &""
var threshold: float = 0.0
var comparison: AbilityTaskWaitAttributeThreshold.Comparison = Comparison.GREATER_OR_EQUAL
var trigger_immediately_if_already_true: bool = false

var matched_value: float = 0.0


static func create(
	ability: GameplayAbility,
	attribute: StringName,
	threshold_value: float,
	comparison_op: AbilityTaskWaitAttributeThreshold.Comparison,
	trigger_immediately: bool = false
) -> AbilityTaskWaitAttributeThreshold:
	var task: AbilityTaskWaitAttributeThreshold = AbilityTaskWaitAttributeThreshold.new()
	task.owner_ability = ability
	task.attribute_name = attribute
	task.threshold = threshold_value
	task.comparison = comparison_op
	task.trigger_immediately_if_already_true = trigger_immediately
	task.target_asc = ability.owner_asc if ability != null else null
	return task


func _on_start() -> void:
	if target_asc == null:
		return
	target_asc.attribute_changed.connect(_on_attribute_changed)
	if trigger_immediately_if_already_true:
		var current: float = target_asc.get_attribute_current(attribute_name)
		if _satisfies(current):
			matched_value = current
			succeed()


func _on_finish() -> void:
	if target_asc != null and target_asc.attribute_changed.is_connected(_on_attribute_changed):
		target_asc.attribute_changed.disconnect(_on_attribute_changed)


func _on_attribute_changed(
	attribute: StringName, _old_value: float, current: float, _effect_spec: GameplayEffectSpec
) -> void:
	if attribute != attribute_name or not _satisfies(current):
		return
	matched_value = current
	succeed()


func _satisfies(value: float) -> bool:
	match comparison:
		Comparison.LESS:
			return value < threshold
		Comparison.LESS_OR_EQUAL:
			return value <= threshold
		Comparison.GREATER:
			return value > threshold
		Comparison.GREATER_OR_EQUAL:
			return value >= threshold
		Comparison.EQUAL_APPROX:
			return is_equal_approx(value, threshold)
	return false
