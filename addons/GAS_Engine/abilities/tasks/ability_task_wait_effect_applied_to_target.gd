## Wait until this ability's owner lands an effect on somebody else.
##
## The other half of `wait_gameplay_effect_applied`, which hears about effects
## arriving here. An ability that wants to react to what it did - a follow-up on
## a successful hit, a resource returned when a debuff lands - was watching the
## wrong end of the same relationship.
##
## Listens to the signal the component already emits when it applies to another
## component. Nothing polls, and nothing new is announced: this is a subscriber
## to something that was already being said.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitEffectAppliedToTarget extends GameplayAbilityTask

## Who it landed on, and what landed.
signal applied_to_target(target: AbilitySystemComponent, spec: GameplayEffectSpec)

## Which effects count. Null means any of them.
var query: GameplayEffectQuery = null

var matched_target: AbilitySystemComponent = null
var matched_spec: GameplayEffectSpec = null


static func create(
	ability: GameplayAbility, query: GameplayEffectQuery = null
) -> AbilityTaskWaitEffectAppliedToTarget:
	var task: AbilityTaskWaitEffectAppliedToTarget = AbilityTaskWaitEffectAppliedToTarget.new()
	task.owner_ability = ability
	task.query = query
	return task


func _on_start() -> void:
	var asc: AbilitySystemComponent = _source_asc()
	if asc != null and not asc.effect_applied_to_target.is_connected(_on_applied):
		asc.effect_applied_to_target.connect(_on_applied)


func _on_finish() -> void:
	var asc: AbilitySystemComponent = _source_asc()
	if asc != null and asc.effect_applied_to_target.is_connected(_on_applied):
		asc.effect_applied_to_target.disconnect(_on_applied)


func _on_applied(target_asc: AbilitySystemComponent, spec: GameplayEffectSpec) -> void:
	if is_finished() or spec == null:
		return
	if query != null and not query.matches_incoming(spec, target_asc):
		return
	matched_target = target_asc
	matched_spec = spec
	applied_to_target.emit(target_asc, spec)
	succeed()


func _source_asc() -> AbilitySystemComponent:
	if owner_ability == null:
		return null
	return owner_ability.owner_asc
