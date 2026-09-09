## Every ability granted, whether it is running, and why it is not.
##
## "Why didn't Fireball go off" is the question this page is for, and it has
## three ordinary answers that look identical from outside: it is on cooldown,
## it is already running, or the last attempt was refused for a reason nobody
## was listening for. All three are columns here.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasDebugPageAbilities extends GasDebugPage

const TITLE: String = "Abilities"
const READY: String = "ready"
const RUNNING: String = "running"
const NEVER_TRIED: String = "-"

## What the runtime calls the result of an activation that worked.
const ACTIVATED: String = "ACTIVATED"


func title() -> String:
	return TITLE


func columns() -> PackedStringArray:
	return PackedStringArray(["Granted ability", "Level", "Running", "Cooldown", "Last result"])


func rows(snapshot: GasRuntimeSnapshot) -> Array[GasDebugPage.Row]:
	var drawn: Array[GasDebugPage.Row] = []
	if snapshot == null:
		return drawn
	for ability: GasRuntimeSnapshot.Ability in snapshot.abilities:
		drawn.append(GasDebugPage.row_of(
			[
				ability.name,
				GasDebugPage.number(ability.level),
				_state_of(ability),
				_cooldown_of(ability),
				ability.last_result if not ability.last_result.is_empty() else NEVER_TRIED,
			],
			# Notable when something is standing in its way, which is when
			# somebody is looking at this page at all.
			ability.on_cooldown or _was_refused(ability)
		))
	return drawn


static func _state_of(ability: GasRuntimeSnapshot.Ability) -> String:
	if not ability.is_running():
		return READY
	return "%s x%d" % [RUNNING, ability.active]


## How much cooldown is left, in whichever unit is counting.
##
## Both, when both are: a turn-based cooldown with a seconds duration is two
## clocks on one grant, and showing one of them is showing half a reason.
static func _cooldown_of(ability: GasRuntimeSnapshot.Ability) -> String:
	if not ability.on_cooldown:
		return READY
	var said: Array[String] = []
	if ability.cooldown_seconds_left > 0.0:
		said.append(GasDebugPage.seconds(ability.cooldown_seconds_left))
	if ability.cooldown_turns_left > 0:
		said.append(GasDebugPage.turns(ability.cooldown_turns_left) + " turns")
	# On cooldown with neither counting down is an infinite one, which is a real
	# state and not a missing number.
	return ", ".join(said) if not said.is_empty() else "on cooldown"


## Whether the last attempt was anything other than an activation.
##
## Read off the name rather than the number, because the number is the runtime's
## and this page is only reporting what it said.
static func _was_refused(ability: GasRuntimeSnapshot.Ability) -> bool:
	return not ability.last_result.is_empty() and ability.last_result != ACTIVATED
