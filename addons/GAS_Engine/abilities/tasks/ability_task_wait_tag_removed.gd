## Wait for a tag pattern to stop matching - not for one specific descendant
## to drop, but for the last one satisfying it to.
##
## Watching `Status.Buffed` while both `Status.Buffed.Strength` and
## `Status.Buffed.Speed` are active does not succeed when only one drops;
## `target_asc.has_tag()` is asked fresh after every removal, the same
## hierarchical rule every other match in this addon uses.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name AbilityTaskWaitTagRemoved extends GameplayAbilityTask

var target_asc: AbilitySystemComponent = null
var watched_tag: StringName = &""


static func create(
	ability: GameplayAbility, tag: StringName, target: AbilitySystemComponent = null
) -> AbilityTaskWaitTagRemoved:
	var task: AbilityTaskWaitTagRemoved = AbilityTaskWaitTagRemoved.new()
	task.owner_ability = ability
	task.watched_tag = tag
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


func _on_start() -> void:
	if target_asc != null:
		target_asc.tag_removed.connect(_on_tag_removed)


func _on_finish() -> void:
	if target_asc != null and target_asc.tag_removed.is_connected(_on_tag_removed):
		target_asc.tag_removed.disconnect(_on_tag_removed)


func _on_tag_removed(tag: StringName) -> void:
	if not GameplayTagRuntime.is_descendant_of(tag, watched_tag):
		return
	if target_asc.has_tag(watched_tag):
		return
	succeed()
