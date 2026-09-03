## Wait for an effect matching a query to be applied to an ASC - INSTANT
## successes included, even though those never get a stable handle.
##
## Reuses `gameplay_effect_application_finished`, the one signal every
## apply_*_result() call already emits - never a second one announcing the
## same application.
##
## Matching is `GameplayEffectQuery.matches_incoming()`: the same evaluator
## immunities ask of a not-yet-active spec, asked here of one that has just
## finished instead. Not `GameplayTagQuery`, which answers about a tag set
## rather than about an effect.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitGameplayEffectApplied extends GameplayAbilityTask

## Fires per match while `trigger_once` is false and the task stays RUNNING.
## `finished` only fires once, on cancel or on the trigger_once match.
signal matched(result: GameplayEffectApplicationResult)

var target_asc: AbilitySystemComponent = null
var query: GameplayEffectQuery = null
var include_periodic: bool = false
var trigger_once: bool = true

var last_result: GameplayEffectApplicationResult = null


static func create(
	ability: GameplayAbility,
	effect_query: GameplayEffectQuery,
	target: AbilitySystemComponent = null,
	include_periodic_ticks: bool = false,
	once: bool = true
) -> AbilityTaskWaitGameplayEffectApplied:
	var task: AbilityTaskWaitGameplayEffectApplied = AbilityTaskWaitGameplayEffectApplied.new()
	task.owner_ability = ability
	task.query = effect_query
	task.include_periodic = include_periodic_ticks
	task.trigger_once = once
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


func _on_start() -> void:
	if target_asc == null:
		return
	target_asc.gameplay_effect_application_finished.connect(_on_application_finished)
	if include_periodic:
		target_asc.gameplay_effect_executed.connect(_on_executed)


func _on_finish() -> void:
	if target_asc == null:
		return
	if target_asc.gameplay_effect_application_finished.is_connected(_on_application_finished):
		target_asc.gameplay_effect_application_finished.disconnect(_on_application_finished)
	if target_asc.gameplay_effect_executed.is_connected(_on_executed):
		target_asc.gameplay_effect_executed.disconnect(_on_executed)


func _on_application_finished(result: GameplayEffectApplicationResult) -> void:
	if not result.is_ok() or not _matches(result.spec):
		return
	_report(result)


func _on_executed(spec: GameplayEffectSpec, active: ActiveGameplayEffect) -> void:
	if not _matches(spec):
		return
	_report(GameplayEffectApplicationResult.ok(spec, active))


func _matches(spec: GameplayEffectSpec) -> bool:
	return query == null or query.matches_incoming(spec, target_asc)


func _report(result: GameplayEffectApplicationResult) -> void:
	last_result = result
	matched.emit(result)
	if trigger_once:
		succeed()
