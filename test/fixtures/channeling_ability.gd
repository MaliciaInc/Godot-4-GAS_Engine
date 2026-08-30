## An ability that stays active until the test lets it finish.
##
## Unconditionally, unlike ProbeAbility's `channels` toggle: that field is not
## `@export`ed, so it never survives PER_EXECUTION's pack-then-instantiate
## round trip - every fresh execution comes back with the class default,
## `false`. Staying open here does not depend on any field surviving that
## trip at all.
##
## @meta_license: MIT
class_name ChannelingAbility extends GameplayAbility

## Held open by the test until it decides this activation is done.
signal channel_gate

## How many times _activate_ability actually ran on this instance.
var activations: int = 0

## Set by the test after activation to see how the input hook read it. Kept
## as a field on the instance itself for the same reason ProbeAbility keeps
## its own - a non-exported one is authored fresh on the running Node, not on
## whatever template supplied the scene.
var presses_while_active: int = 0


func _activate_ability() -> bool:
	activations += 1
	await channel_gate
	return true


func _active_input_pressed(_asc: AbilitySystemComponent) -> void:
	presses_while_active += 1
