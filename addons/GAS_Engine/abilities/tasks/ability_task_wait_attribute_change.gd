## Wait for one attribute on one ASC to actually move.
##
## Connects to the ASC's own `attribute_changed` directly - that signal
## already never fires for a write that resolved to the same value, so this
## task adds no filtering logic of its own beyond the attribute name.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitAttributeChange extends GameplayAbilityTask

var target_asc: AbilitySystemComponent = null
var attribute_name: StringName = &""

var old_value: float = 0.0
var new_value: float = 0.0
## The effect whose write caused the change, or null for a direct base edit.
var source_spec: GameplayEffectSpec = null


static func create(
	ability: GameplayAbility, attribute: StringName, target: AbilitySystemComponent = null
) -> AbilityTaskWaitAttributeChange:
	var task: AbilityTaskWaitAttributeChange = AbilityTaskWaitAttributeChange.new()
	task.owner_ability = ability
	task.attribute_name = attribute
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


func _on_start() -> void:
	if target_asc != null:
		target_asc.attribute_changed.connect(_on_attribute_changed)


func _on_finish() -> void:
	if target_asc != null and target_asc.attribute_changed.is_connected(_on_attribute_changed):
		target_asc.attribute_changed.disconnect(_on_attribute_changed)


func _on_attribute_changed(
	attribute: StringName, previous: float, current: float, effect_spec: GameplayEffectSpec
) -> void:
	if attribute != attribute_name:
		return
	old_value = previous
	new_value = current
	source_spec = effect_spec
	succeed()
