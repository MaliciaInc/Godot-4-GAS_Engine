## Wait for another ability to end - by its exact handle, or by a
## GameplayTagQuery over its effective ability tags. The same filter shape as
## AbilityTaskWaitAbilityActivated, watching Task 17's `ability_runtime_ended`
## instead.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitAbilityEnded extends GameplayAbilityTask

var target_asc: AbilitySystemComponent = null
var watched_handle: GameplayAbilityHandle = null
var query: GameplayTagQuery = null

var matched_handle: GameplayAbilityHandle = null
var matched_instance: GameplayAbility = null
var was_cancelled: bool = false
var end_reason: GameplayAbilityTask.CancelReason = GameplayAbilityTask.CancelReason.NONE


static func create(
	ability: GameplayAbility, handle: GameplayAbilityHandle, target: AbilitySystemComponent = null
) -> AbilityTaskWaitAbilityEnded:
	var task: AbilityTaskWaitAbilityEnded = AbilityTaskWaitAbilityEnded.new()
	task.owner_ability = ability
	task.watched_handle = handle
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


static func create_matching(
	ability: GameplayAbility, tag_query: GameplayTagQuery, target: AbilitySystemComponent = null
) -> AbilityTaskWaitAbilityEnded:
	var task: AbilityTaskWaitAbilityEnded = AbilityTaskWaitAbilityEnded.new()
	task.owner_ability = ability
	task.query = tag_query
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


func _on_start() -> void:
	if target_asc != null:
		target_asc.ability_runtime_ended.connect(_on_ended)


func _on_finish() -> void:
	if target_asc != null and target_asc.ability_runtime_ended.is_connected(_on_ended):
		target_asc.ability_runtime_ended.disconnect(_on_ended)


func _on_ended(
	handle: GameplayAbilityHandle,
	instance: GameplayAbility,
	cancelled: bool,
	reason: GameplayAbilityTask.CancelReason
) -> void:
	if not _matches(handle):
		return
	matched_handle = handle
	matched_instance = instance
	was_cancelled = cancelled
	end_reason = reason
	succeed()


func _matches(handle: GameplayAbilityHandle) -> bool:
	if query != null:
		var spec: GameplayAbilitySpec = target_asc.ability_runtime.get_spec(handle)
		return query.matches_tags(AbilityTagSemanticsRuntime.effective_ability_tags(spec))
	return watched_handle != null and handle != null and handle.same_as(watched_handle)
