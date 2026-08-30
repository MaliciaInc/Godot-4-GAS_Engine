## Wait for a gameplay event, matched the way every other listener matches.
##
## Tags are hierarchical in one direction: a task waiting on `Event.Damage` is
## woken by `Event.Damage.Critical`, and one waiting on the critical is not woken
## by the general case.
##
## That rule is asked of `GameplayEventRuntime`, never re-implemented here. A
## second copy would eventually disagree with the first, and the disagreement
## would surface as an ability that woke for the wrong event - or worse, one that
## quietly never woke at all.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name AbilityTaskWaitGameplayEvent extends GameplayAbilityTask

var event_tag: StringName = &""

## The event that ended the wait, kept so the ability can read what it carried
## rather than having to catch it separately.
var matched_event: GameplayEventData = null


static func create(ability: GameplayAbility, tag: StringName) -> AbilityTaskWaitGameplayEvent:
	var task: AbilityTaskWaitGameplayEvent = AbilityTaskWaitGameplayEvent.new()
	task.owner_ability = ability
	task.event_tag = tag
	return task


func handle_gameplay_event(event: GameplayEventData) -> void:
	if event == null:
		return
	if not GameplayEventRuntime.matches(event.event_tag, event_tag):
		return
	matched_event = event
	succeed()
