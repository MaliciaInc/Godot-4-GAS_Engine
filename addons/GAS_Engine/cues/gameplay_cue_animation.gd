## Firing a cue from an animation, where an animation is the only thing that
## knows the moment.
##
## A footstep lands on a frame, not on a tick, and the thing that knows which
## frame is the AnimationPlayer. A method track calls this with a tag, and the
## cue plays on whichever entity the animation belongs to.
##
## Static because a method track calls a method on a node, and the node it calls
## is whatever the track points at - there is nowhere to hold an instance. The
## work is finding the ability system from a node inside the character, which is
## exactly what AbilitySystemLocator already does.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCueAnimation extends RefCounted


## Play `tag` on whoever `target` belongs to.
##
## Silent when the node is not part of an ability system: an animation playing
## on a prop that has no ASC is an ordinary thing, and an error every frame of
## it would be noise rather than information.
## @composer
static func fire(target: Node, tag: StringName) -> void:
	if target == null or not is_instance_valid(target) or tag == &"":
		return
	var asc: AbilitySystemComponent = AbilitySystemLocator.find_for_node(target)
	if asc == null:
		return
	asc.execute_cue(GameplayCueParams.for_target(tag, target, asc.get_effect_target(), 0.0))
