## Wait until something is turned away by an immunity.
##
## The moment a design needs and nothing announced: a cleanse that fires when a
## debuff bounces, a shield that flashes when it stops something, a tutorial
## that says why nothing happened. Without it the only observable is that the
## effect did not land, which is also what happens when it was never applied.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitEffectBlockedByImmunity extends GameplayAbilityTask

var target_asc: AbilitySystemComponent = null

## What was turned away, and by what it was refused.
var blocked: GameplayEffectApplicationResult = null


static func create(
	ability: GameplayAbility, target: AbilitySystemComponent = null
) -> AbilityTaskWaitEffectBlockedByImmunity:
	var task: AbilityTaskWaitEffectBlockedByImmunity = (
		AbilityTaskWaitEffectBlockedByImmunity.new()
	)
	task.owner_ability = ability
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


func _on_start() -> void:
	if target_asc != null:
		target_asc.gameplay_effect_application_finished.connect(_on_finished)


func _on_finish() -> void:
	if target_asc == null:
		return
	if target_asc.gameplay_effect_application_finished.is_connected(_on_finished):
		target_asc.gameplay_effect_application_finished.disconnect(_on_finished)


func _on_finished(result: GameplayEffectApplicationResult) -> void:
	if result == null or result.status != GameplayEffectApplicationResult.Status.IMMUNE:
		return
	blocked = result
	succeed()
