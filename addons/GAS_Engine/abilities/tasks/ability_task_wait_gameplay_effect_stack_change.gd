## Wait for one active effect's stack count to change - growth or overflow's
## non-growing rejection never fires this, since T12's own signal only fires
## when the count actually moved.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitGameplayEffectStackChange extends GameplayAbilityTask

var target_asc: AbilitySystemComponent = null
var watched_handle: GameplayEffectHandle = null

var old_count: int = 0
var new_count: int = 0


static func create(
	ability: GameplayAbility, handle: GameplayEffectHandle, target: AbilitySystemComponent = null
) -> AbilityTaskWaitGameplayEffectStackChange:
	var task: AbilityTaskWaitGameplayEffectStackChange = AbilityTaskWaitGameplayEffectStackChange.new()
	task.owner_ability = ability
	task.watched_handle = handle
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


func _on_start() -> void:
	if target_asc != null:
		target_asc.active_effect_stack_changed.connect(_on_stack_changed)


func _on_finish() -> void:
	if target_asc != null and target_asc.active_effect_stack_changed.is_connected(_on_stack_changed):
		target_asc.active_effect_stack_changed.disconnect(_on_stack_changed)


func _on_stack_changed(handle: GameplayEffectHandle, previous: int, current: int) -> void:
	if watched_handle == null or handle == null or not handle.same_as(watched_handle):
		return
	old_count = previous
	new_count = current
	succeed()
