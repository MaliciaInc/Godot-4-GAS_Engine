## The last hundred and twenty-eight things that happened to a target's
## attributes.
##
## "Health went to zero" is never the question; "what took it there" is, and by
## the time somebody opens an overlay the change they care about has already
## happened. A current value answers nothing about a fight that is over.
##
## Bounded on purpose, and bounded per target. An unbounded log of every
## attribute change in a running game is a memory leak with a nice name on it -
## a periodic effect ticking twice a second fills a hundred thousand entries in
## an afternoon, and nobody scrolls back that far.
##
## Records rather than instruments: the component already announces every
## change, so this listens. Announcing it a second time at each site would be a
## second description of what happened, and the two would disagree the first
## time one of them was updated.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasAttributeHistory extends RefCounted

## How many changes are kept per target unless somebody says otherwise.
const DEFAULT_LIMIT: int = 128


## One attribute change, as it happened.
class Change extends RefCounted:
	var attribute_name: StringName = &""
	var from_value: float = 0.0
	var to_value: float = 0.0

	## Milliseconds since the engine started, which is what a person comparing
	## two entries needs and is all a running game can cheaply say.
	var at_msec: int = 0

	## Where this sits in everything this history has ever recorded, so an
	## entry can still be placed after older ones have fallen off the end.
	var ordinal: int = 0

	func delta() -> float:
		return to_value - from_value

	func shown() -> String:
		return "%s %s -> %s" % [String(attribute_name), from_value, to_value]


var limit: int = DEFAULT_LIMIT

## Oldest first, which is the order they happened in.
var _changes: Array[Change] = []

## How many have ever been recorded, including the ones dropped off the front.
var _recorded: int = 0

var _watched: AbilitySystemComponent = null


## Start recording what happens to `component`.
##
## Answers whether it attached, so a caller can tell "nothing is being watched"
## from "watched, and nothing has happened" - which look the same in an empty
## list and are the first thing somebody wonders about.
func watch(component: AbilitySystemComponent) -> bool:
	if component == null:
		return false
	stop()
	_watched = component
	component.attribute_changed.connect(_on_attribute_changed)
	return true


## Stop recording, and let go of the component.
##
## Every connection this made, taken back: a component that outlives the
## history and still holds callables into it is the shape of leak the dispose
## work in F5.1.2 was about.
func stop() -> void:
	if _watched == null:
		return
	if _watched.attribute_changed.is_connected(_on_attribute_changed):
		_watched.attribute_changed.disconnect(_on_attribute_changed)
	_watched = null


## Note one change, dropping the oldest when the limit is reached.
##
## Public so a game can record something the engine does not announce - a stat
## its own code moved - through the same bounded list rather than keeping a
## second one beside it.
func record(attribute_name: StringName, from_value: float, to_value: float) -> Change:
	var change: Change = Change.new()
	change.attribute_name = attribute_name
	change.from_value = from_value
	change.to_value = to_value
	change.at_msec = Time.get_ticks_msec()
	change.ordinal = _recorded
	_recorded += 1

	_changes.append(change)
	# A limit of zero or less records nothing rather than everything: "keep none"
	# is a thing somebody can mean, and growing without bound is not.
	while _changes.size() > maxi(limit, 0):
		_changes.remove_at(0)
	return change


## Everything kept, newest first.
##
## Newest first because that is the end somebody reads: an overlay showing the
## oldest hundred entries of a fight is showing the part that is already over.
func recent(count: int = 0) -> Array[Change]:
	var wanted: int = count if count > 0 else _changes.size()
	var found: Array[Change] = []
	var index: int = _changes.size() - 1
	while index >= 0 and found.size() < wanted:
		found.append(_changes[index])
		index -= 1
	return found


## Everything about one attribute, newest first.
func recent_for(attribute_name: StringName) -> Array[Change]:
	var found: Array[Change] = []
	for change: Change in recent():
		if change.attribute_name == attribute_name:
			found.append(change)
	return found


## How many are kept right now.
func size() -> int:
	return _changes.size()


## How many have ever been recorded, including those dropped.
##
## The number that says a history is bounded rather than empty: a list of 128
## entries after a long fight is not the same as a list of 128 entries after
## 128 changes, and only this tells them apart.
func recorded() -> int:
	return _recorded


func forget() -> void:
	_changes.clear()
	_recorded = 0


func _on_attribute_changed(
	attribute_name: StringName, old_value: float, new_value: float, _spec: GameplayEffectSpec
) -> void:
	record(attribute_name, old_value, new_value)
