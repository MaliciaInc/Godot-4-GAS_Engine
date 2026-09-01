## Wait for another ability to start - by its exact handle, or by a
## GameplayTagQuery over its effective ability tags.
##
## Reuses Task 17's `ability_activated` and Task 15's
## `AbilityTagSemanticsRuntime.effective_ability_tags()` - never a second
## reading of what an ability's tags are.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name AbilityTaskWaitAbilityActivated extends GameplayAbilityTask

var target_asc: AbilitySystemComponent = null
var watched_handle: GameplayAbilityHandle = null
var query: GameplayTagQuery = null

var matched_handle: GameplayAbilityHandle = null
var matched_instance: GameplayAbility = null


static func create(
	ability: GameplayAbility, handle: GameplayAbilityHandle, target: AbilitySystemComponent = null
) -> AbilityTaskWaitAbilityActivated:
	var task: AbilityTaskWaitAbilityActivated = AbilityTaskWaitAbilityActivated.new()
	task.owner_ability = ability
	task.watched_handle = handle
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


static func create_matching(
	ability: GameplayAbility, tag_query: GameplayTagQuery, target: AbilitySystemComponent = null
) -> AbilityTaskWaitAbilityActivated:
	var task: AbilityTaskWaitAbilityActivated = AbilityTaskWaitAbilityActivated.new()
	task.owner_ability = ability
	task.query = tag_query
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


func _on_start() -> void:
	if target_asc != null:
		target_asc.ability_activated.connect(_on_activated)


func _on_finish() -> void:
	if target_asc != null and target_asc.ability_activated.is_connected(_on_activated):
		target_asc.ability_activated.disconnect(_on_activated)


func _on_activated(handle: GameplayAbilityHandle, instance: GameplayAbility) -> void:
	if not _matches(handle):
		return
	matched_handle = handle
	matched_instance = instance
	succeed()


func _matches(handle: GameplayAbilityHandle) -> bool:
	if query != null:
		var spec: GameplayAbilitySpec = target_asc.ability_runtime.get_spec(handle)
		return query.matches_tags(AbilityTagSemanticsRuntime.effective_ability_tags(spec))
	return watched_handle != null and handle != null and handle.same_as(watched_handle)
