## Wait for an arbitrary GameplayTagQuery to reach a desired true/false on an
## ASC - the general case AbilityTaskWaitTagAdded/Removed cover the common
## single-tag shape of.
##
## Any tag change can flip a query's result, so this listens to all three tag
## signals and re-asks `GameplayTagQuery.matches_runtime()` - the one place
## query evaluation lives, never reimplemented here.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitTagQuery extends GameplayAbilityTask

var target_asc: AbilitySystemComponent = null
var query: GameplayTagQuery = null
var desired: bool = true


static func create(
	ability: GameplayAbility,
	tag_query: GameplayTagQuery,
	desired_result: bool = true,
	target: AbilitySystemComponent = null
) -> AbilityTaskWaitTagQuery:
	var task: AbilityTaskWaitTagQuery = AbilityTaskWaitTagQuery.new()
	task.owner_ability = ability
	task.query = tag_query
	task.desired = desired_result
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


func _on_start() -> void:
	if target_asc == null or query == null:
		return
	target_asc.tag_added.connect(_on_tag_changed)
	target_asc.tag_removed.connect(_on_tag_changed)
	target_asc.tag_count_changed.connect(_on_tag_count_changed)
	_check()


func _on_finish() -> void:
	if target_asc == null:
		return
	if target_asc.tag_added.is_connected(_on_tag_changed):
		target_asc.tag_added.disconnect(_on_tag_changed)
	if target_asc.tag_removed.is_connected(_on_tag_changed):
		target_asc.tag_removed.disconnect(_on_tag_changed)
	if target_asc.tag_count_changed.is_connected(_on_tag_count_changed):
		target_asc.tag_count_changed.disconnect(_on_tag_count_changed)


func _on_tag_changed(_tag: StringName) -> void:
	_check()


func _on_tag_count_changed(_tag: StringName, _new_count: int) -> void:
	_check()


func _check() -> void:
	if query.matches_runtime(target_asc.tags) == desired:
		succeed()
