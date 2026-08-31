## Wait for a tag - or any descendant of it - to become active on an ASC.
##
## Hierarchical, the same rule `GameplayTagRuntime.is_descendant_of` already
## implements everywhere else a tag pattern is matched: watching
## `Status.Buffed` wakes on `Status.Buffed.Strength` too.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name AbilityTaskWaitTagAdded extends GameplayAbilityTask

var target_asc: AbilitySystemComponent = null
var watched_tag: StringName = &""

## The exact tag whose count crossed 0 -> 1, which may be a descendant of
## `watched_tag` rather than an exact match.
var matched_tag: StringName = &""


static func create(
	ability: GameplayAbility, tag: StringName, target: AbilitySystemComponent = null
) -> AbilityTaskWaitTagAdded:
	var task: AbilityTaskWaitTagAdded = AbilityTaskWaitTagAdded.new()
	task.owner_ability = ability
	task.watched_tag = tag
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


func _on_start() -> void:
	if target_asc != null:
		target_asc.tag_added.connect(_on_tag_added)


func _on_finish() -> void:
	if target_asc != null and target_asc.tag_added.is_connected(_on_tag_added):
		target_asc.tag_added.disconnect(_on_tag_added)


func _on_tag_added(tag: StringName) -> void:
	if not GameplayTagRuntime.is_descendant_of(tag, watched_tag):
		return
	matched_tag = tag
	succeed()
