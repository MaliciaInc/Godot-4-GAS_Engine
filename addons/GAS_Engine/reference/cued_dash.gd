## A dash that tells the game to show something, twice.
##
## Cues are the seam between what an ability does and what a player sees. The
## ability never touches a particle, a sound or an animation - it says a tag, and
## whatever the game registered for that tag runs. An ability that reached for a
## node would be an ability that only works in one game.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
extends GameplayAbility

## Fired the moment the dash starts.
@export var launch_cue: StringName = &"Cue.Dash.Launch"

## Fired when it is over, whether or not anything was hit.
@export var landing_cue: StringName = &"Cue.Dash.Land"

@export var haste: GameplayEffect

## How long the dash lasts, in seconds.
@export var travel_time: float = 0.35


func _activate_ability() -> bool:
	if not commit_ability().is_ok():
		return false

	execute_cue(launch_cue)
	owner_asc.apply_gameplay_effect(haste, owner_asc, get_ability_level())

	var travel: AbilityTaskWaitDelay = wait_delay(travel_time)
	await travel.finished

	execute_cue(landing_cue)
	end_ability()
	return true
