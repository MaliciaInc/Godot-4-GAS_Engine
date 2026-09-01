## Wait for one active effect to be removed - by its exact handle (the
## default), or by a GameplayEffectQuery when the caller wants any effect
## matching a shape rather than one specific instance.
##
## Reuses `gameplay_effect_removal_finished`, T13's typed superset of
## `active_effect_removed` that already carries the RemovalReason.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name AbilityTaskWaitGameplayEffectRemoved extends GameplayAbilityTask

var target_asc: AbilitySystemComponent = null
var watched_handle: GameplayEffectHandle = null
var query: GameplayEffectQuery = null

var matched_active_effect: ActiveGameplayEffect = null
var removal_reason: ActiveGameplayEffect.RemovalReason = ActiveGameplayEffect.RemovalReason.EXPLICIT


static func create(
	ability: GameplayAbility, handle: GameplayEffectHandle, target: AbilitySystemComponent = null
) -> AbilityTaskWaitGameplayEffectRemoved:
	var task: AbilityTaskWaitGameplayEffectRemoved = AbilityTaskWaitGameplayEffectRemoved.new()
	task.owner_ability = ability
	task.watched_handle = handle
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


static func create_matching(
	ability: GameplayAbility, effect_query: GameplayEffectQuery, target: AbilitySystemComponent = null
) -> AbilityTaskWaitGameplayEffectRemoved:
	var task: AbilityTaskWaitGameplayEffectRemoved = AbilityTaskWaitGameplayEffectRemoved.new()
	task.owner_ability = ability
	task.query = effect_query
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


func _on_start() -> void:
	if target_asc != null:
		target_asc.gameplay_effect_removal_finished.connect(_on_removed)


func _on_finish() -> void:
	if target_asc != null and target_asc.gameplay_effect_removal_finished.is_connected(_on_removed):
		target_asc.gameplay_effect_removal_finished.disconnect(_on_removed)


func _on_removed(active: ActiveGameplayEffect, reason: ActiveGameplayEffect.RemovalReason) -> void:
	if query != null:
		if not query.matches(active, target_asc):
			return
	elif watched_handle == null or active.handle == null or not active.handle.same_as(watched_handle):
		return
	matched_active_effect = active
	removal_reason = reason
	succeed()
