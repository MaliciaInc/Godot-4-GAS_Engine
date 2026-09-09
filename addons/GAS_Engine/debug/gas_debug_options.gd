## The switches QA flips, in one place instead of five.
##
## Two of them - costs and cooldowns - are for a person testing an ability
## twenty times in a row without waiting for it or farming for mana. They exist
## in debug builds and nowhere else: a shipped game in which somebody can turn
## costs off is a shipped game in which somebody will.
##
## "Only in a debug build" is enforced where it is read, not only where it is
## written. A build that somehow arrived with a switch already on still behaves
## as though it were off, because the question a release build asks answers
## itself before it looks.
##
## Neither switch touches an attribute. `ignore_costs` does not top anybody up
## and `ignore_cooldowns` does not clear a tag - they are asked in the preflight
## that would have refused, so the moment they are turned off again the entity
## is in exactly the state it was going to be in. A debug switch that mutated
## state would leave a save file somebody debugged in.
##
## The other two are not debug switches at all. They are the process-wide half
## of what a component already declares for itself, so a test bench or a
## dedicated server can say it once rather than on every component it builds.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasDebugOptions extends RefCounted

## What each switch is called, wherever one is named to a person.
const IGNORE_COSTS: StringName = &"ignore_costs"
const IGNORE_COOLDOWNS: StringName = &"ignore_cooldowns"
const SUPPRESS_CUES: StringName = &"suppress_cues"
const SUPPRESS_ABILITY_GRANTS: StringName = &"suppress_ability_grants"

const ONLY_IN_DEBUG: String = (
	"GAS_Engine: '%s' is a debug-build switch. This is a release build, so "
	+ "nothing was changed and nothing behaves differently."
)
const CHANGED: String = "GAS_Engine: '%s' is now %s."
const ON: String = "on"
const OFF: String = "off"

## Set rather than exported: these are process-wide, and a process has one of
## each. A component's own suppression is still its own and is asked alongside
## these, never replaced by them.
static var _switches: Dictionary[StringName, bool] = {
	IGNORE_COSTS: false,
	IGNORE_COOLDOWNS: false,
	SUPPRESS_CUES: false,
	SUPPRESS_ABILITY_GRANTS: false,
}

## The two that only exist in a debug build.
static var _debug_only: Array[StringName] = [IGNORE_COSTS, IGNORE_COOLDOWNS]


#region Asking
## Whether costs are being ignored right now.
##
## Read at the preflight that would refuse for cost and at the one that would
## take it, so an ability activates for free and the entity's resources are
## exactly where they were.
static func costs_ignored() -> bool:
	return is_on(IGNORE_COSTS)


## Whether cooldowns are being ignored right now.
##
## Read at the gate rather than by clearing a tag, and read again where a
## cooldown would be started - so nothing is running that a UI would draw as a
## wait the player is not actually having.
static func cooldowns_ignored() -> bool:
	return is_on(IGNORE_COOLDOWNS)


## Whether cues are switched off for the whole process.
##
## Not the same statement as "do not tell anybody a cue happened": a dedicated
## server plays nothing and still has to say what occurred, and a switch that
## meant both would make that impossible to express. Replication has its own
## answer and this is not it.
static func cues_suppressed() -> bool:
	return is_on(SUPPRESS_CUES)


## Whether ability grants are refused for the whole process.
static func ability_grants_suppressed() -> bool:
	return is_on(SUPPRESS_ABILITY_GRANTS)


## Whether one switch is on, by name.
##
## A debug-only switch is off in a release build whatever it was set to. The
## guard is here rather than only in the setter because that is the half that
## cannot be got around: however the value arrived, this is what is asked.
static func is_on(switch: StringName) -> bool:
	if not exists_in(switch, OS.is_debug_build()):
		return false
	return _switches[switch]


## Whether a switch does anything at all in a build of this kind.
##
## The build is a parameter rather than asked here, because "does nothing in a
## release build" is the promise worth checking and a test running in a debug
## build cannot become a release one to check it. Every caller inside this file
## passes `OS.is_debug_build()`; a test passes false and gets the release
## answer.
static func exists_in(switch: StringName, a_debug_build: bool) -> bool:
	if not _switches.has(switch):
		return false
	return a_debug_build or not _debug_only.has(switch)


## Whether this switch only exists in a debug build.
static func is_debug_only(switch: StringName) -> bool:
	return _debug_only.has(switch)


## Every switch there is, so a console can list them without a second list.
static func declared() -> Array[StringName]:
	var found: Array[StringName] = []
	found.assign(_switches.keys())
	return found
#endregion


#region Setting
## Turn one switch on or off, and say what happened.
##
## Answers the sentence rather than a bool, because every caller is about to
## show somebody a line: a switch refused in a release build has to say why, and
## "false" does not.
static func set_switch(switch: StringName, on: bool) -> String:
	if not _switches.has(switch):
		return ""
	if not exists_in(switch, OS.is_debug_build()):
		return ONLY_IN_DEBUG % String(switch)
	_switches[switch] = on
	return CHANGED % [String(switch), ON if on else OFF]


## Put every switch back to off.
##
## For a test, and for a QA session that wants to start over: what makes these
## safe is that turning them off puts the entity back where it was, and there
## has to be one call that does all of it.
static func forget() -> void:
	for switch: StringName in _switches:
		_switches[switch] = false
#endregion
