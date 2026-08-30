## An ability whose active-input-pressed hook ends it immediately.
##
## Proves a dispatch loop snapshots its targets before delivering: when
## several instances of one PER_EXECUTION spec are live together, one of them
## ending itself as a direct result of the transition it just received must
## not make the loop skip its neighbour.
##
## @meta_license: MIT
class_name SelfEndingAbility extends GameplayAbility

## Held open by the test until it decides this activation is done.
signal channel_gate

var active_input_presses: int = 0


func _activate_ability() -> bool:
	await channel_gate
	return true


func _active_input_pressed(_asc: AbilitySystemComponent) -> void:
	active_input_presses += 1
	end_ability()
