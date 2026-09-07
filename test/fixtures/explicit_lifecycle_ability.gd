## An ability that says when it is finished, and records what it was told.
##
## Two things at once, on purpose: it outlives its own activation function - so
## a test can see that returning did not end it - and it counts every hook the
## engine calls on it, so a test can see that it was told rather than left to
## find out.
##
## The counters are per instance and not exported, which is what makes them
## usable for the NON_INSTANCED case: two concurrent activations that could see
## each other's counters would be sharing the Node the policy forbids sharing.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name ExplicitLifecycleAbility extends GameplayAbility

## How many times `_activate_ability` actually ran on this instance.
var activations: int = 0

## What the engine told this instance, in order.
var told: Array[String] = []

## Set false by a test that wants this ability to refuse being cancelled.
var cancellable: bool = true


func _activate_ability() -> bool:
	activations += 1
	return true


func on_granted() -> void:
	told.append("granted")


## Records what it could still see at the moment it was told.
##
## Whether the hook runs before anything is severed cannot be read afterwards -
## by then everything is severed either way - so it is observed here, from
## inside the call.
func on_removed() -> void:
	told.append("removed" if owner_asc != null else "removed after being cut loose")


func on_avatar_changed(old_avatar: Node, new_avatar: Node) -> void:
	told.append("avatar %s -> %s" % [old_avatar.name, new_avatar.name])


func can_be_cancelled() -> bool:
	return cancellable
