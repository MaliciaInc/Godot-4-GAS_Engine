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
## Three things it can be told, each of which was a loop somebody wrote by hand
## before: keep listening rather than end on the first match, match only the
## exact tag, and listen to somebody else's component. The last one connects to
## a signal rather than waiting to be handed events, because the runtime only
## routes to tasks owned by its own abilities - and whatever it connects, it
## disconnects on the way out.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitGameplayEvent extends GameplayAbilityTask

## Emitted for every match. On a one-shot this fires once, immediately before
## the task succeeds.
signal event_received(event: GameplayEventData)

var event_tag: StringName = &""

## The event that ended the wait, kept so the ability can read what it carried
## rather than having to catch it separately. On a continuous task this is the
## most recent one; `event_received` carries each.
var matched_event: GameplayEventData = null

## Whether the first match ends the wait.
##
## False makes this a listener rather than a wait: it emits `event_received` for
## every match and stays until the ability ends or somebody cancels it. An
## ability that wants "every time I am hit, while I channel" had to wrap a
## one-shot in a loop before, and a loop is a thing that can be left running.
var only_trigger_once: bool = true

## Whether a child tag counts.
##
## The hierarchy is the default because it is what a listener usually means. An
## ability that must not hear `Event.Damage.Critical` while waiting on
## `Event.Damage` says so, and then the comparison is equality.
var only_match_exact: bool = false

## Whose events this listens to. Null means the ability's own component, which
## is the ordinary case and needs no connection at all.
var from_asc: AbilitySystemComponent = null


static func create(
	ability: GameplayAbility,
	tag: StringName,
	only_trigger_once: bool = true,
	only_match_exact: bool = false,
	from_asc: AbilitySystemComponent = null
) -> AbilityTaskWaitGameplayEvent:
	var task: AbilityTaskWaitGameplayEvent = AbilityTaskWaitGameplayEvent.new()
	task.owner_ability = ability
	task.event_tag = tag
	task.only_trigger_once = only_trigger_once
	task.only_match_exact = only_match_exact
	task.from_asc = from_asc
	return task


## Connect to the other component, when there is one.
##
## Only then: the ability's own component already routes its events here through
## the task runtime, and connecting to that as well would deliver each event
## twice.
func _on_start() -> void:
	if not _listens_elsewhere():
		return
	if not from_asc.gameplay_event_received.is_connected(handle_gameplay_event):
		from_asc.gameplay_event_received.connect(handle_gameplay_event)


## Always, however the task ended. One that stopped listening only when it
## succeeded would keep answering a component it no longer belongs to.
func _on_finish() -> void:
	if not _listens_elsewhere():
		return
	if from_asc.gameplay_event_received.is_connected(handle_gameplay_event):
		from_asc.gameplay_event_received.disconnect(handle_gameplay_event)


func handle_gameplay_event(event: GameplayEventData) -> void:
	if event == null or is_finished():
		return
	if not _matches(event.event_tag):
		return
	matched_event = event
	event_received.emit(event)
	if only_trigger_once:
		succeed()


func _matches(dispatched: StringName) -> bool:
	if only_match_exact:
		return dispatched == event_tag
	return GameplayEventRuntime.matches(dispatched, event_tag)


## Whether this task is listening to a component other than its own ability's.
func _listens_elsewhere() -> bool:
	if from_asc == null or not is_instance_valid(from_asc):
		return false
	return owner_ability == null or from_asc != owner_ability.owner_asc
