## Wait until how many of a tag an entity holds changes.
##
## Not the same question as "did it arrive". A stack of three poisons going to
## two is a change nothing else announces: the tag is still on, `tag_added`
## fired once at the start, and an ability that scales with the stack has no
## way to notice.
##
## Watches the family, the way every other tag matcher in this engine does:
## a task on `State` wakes when `State.Stunned` moves.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitTagCountChange extends GameplayAbilityTask

var target_asc: AbilitySystemComponent = null
var watched_tag: StringName = &""

## What it changed to, and what it was.
var new_count: int = 0
var old_count: int = 0


static func create(
	ability: GameplayAbility, tag: StringName, target: AbilitySystemComponent = null
) -> AbilityTaskWaitTagCountChange:
	var task: AbilityTaskWaitTagCountChange = AbilityTaskWaitTagCountChange.new()
	task.owner_ability = ability
	task.watched_tag = tag
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


func _on_start() -> void:
	if target_asc == null:
		return
	old_count = target_asc.tags.count(watched_tag)
	target_asc.tag_or_child_count_changed.connect(_on_count_changed)


func _on_finish() -> void:
	if target_asc == null:
		return
	if target_asc.tag_or_child_count_changed.is_connected(_on_count_changed):
		target_asc.tag_or_child_count_changed.disconnect(_on_count_changed)


func _on_count_changed(tag: StringName, count: int) -> void:
	if tag != watched_tag:
		return
	new_count = count
	succeed()
