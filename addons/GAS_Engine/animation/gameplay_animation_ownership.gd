## Who owns the playback a mixer is currently running.
##
## Two abilities on one character reach for the same AnimationPlayer, and the
## second one wins: Godot's `play()` simply replaces what was running, and says
## nothing to whoever asked first. The task that was waiting on the first
## animation is then waiting for an `animation_finished` that will never carry
## its name, so it waits until the ability ends - holding its cost, its tags and
## whatever else the ability took.
##
## What was missing is not a lock. Taking the animation over is a legitimate
## thing for the second ability to do; what the first one needs is a way to find
## out that it happened.
##
## The claim lives on the mixer itself, as metadata. That is where both sides
## can see it without either knowing about the other, and it dies with the node
## rather than outliving the scene in a registry nothing clears.
##
## A receipt keeps the mixer by id rather than by reference, and the two
## questions asked late - is this still mine, give it back - take no arguments
## because of it. A node freed while an ability was still animating it is the
## ordinary case rather than the exception, and a method typed `AnimationMixer`
## cannot be handed one that has been freed: Godot refuses the call at the
## argument, so a validity check written inside the method never runs at all.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAnimationOwnership extends RefCounted

const META_KEY: StringName = &"gas_engine_animation_owner"

## Which ability instance, and which of that instance's activations.
##
## Both, because a retriggered ability is a new activation of the same
## instance, and the animation the previous activation started is not this
## one's to wait on.
var owner_instance_id: int = 0
var activation_id: int = 0
var animation: StringName = &""

## The mixer this was taken on, held by id so it can still be asked about after
## the node itself is gone.
var _mixer_id: int = 0


## Take the mixer, and hand back the receipt that says so.
static func claim(
	mixer: AnimationMixer, ability: GameplayAbility, animation_name: StringName
) -> GameplayAnimationOwnership:
	if mixer == null or not is_instance_valid(mixer):
		return null
	var taken: GameplayAnimationOwnership = GameplayAnimationOwnership.new()
	taken.owner_instance_id = ability.get_instance_id() if ability != null else 0
	taken.activation_id = ability.activation_id if ability != null else 0
	taken.animation = animation_name
	taken._mixer_id = mixer.get_instance_id()
	mixer.set_meta(META_KEY, taken)
	return taken


## Who holds a mixer now, or null when nobody does.
##
## Takes the node, so it is for a caller holding a live one - asking who owns a
## surface before reaching for it. The receipt's own questions below are the
## ones meant for later.
static func holder_of(mixer: AnimationMixer) -> GameplayAnimationOwnership:
	if mixer == null or not is_instance_valid(mixer) or not mixer.has_meta(META_KEY):
		return null
	var held: GameplayAnimationOwnership = mixer.get_meta(META_KEY)
	return held


func same_as(other: GameplayAnimationOwnership) -> bool:
	return (
		other != null
		and other.owner_instance_id == owner_instance_id
		and other.activation_id == activation_id
		and other.animation == animation
	)


## The mixer this was taken on, or null once it is gone.
func mixer() -> AnimationMixer:
	if _mixer_id == 0 or not is_instance_id_valid(_mixer_id):
		return null
	var found: AnimationMixer = instance_from_id(_mixer_id) as AnimationMixer
	return found


## Whether this receipt is still the one the mixer records.
##
## False once the node is gone, which is the answer the caller wants: an
## animation whose surface no longer exists is not one anybody is still
## waiting on.
func still_holds() -> bool:
	var surface: AnimationMixer = mixer()
	if surface == null:
		return false
	return same_as(GameplayAnimationOwnership.holder_of(surface))


## Give it back, but only while it is still ours.
##
## A task cleaning up after it was already replaced must not take the new
## owner's claim away with it - that would leave the surface reading as unowned
## while an animation somebody else started is playing on it.
func release() -> void:
	if not still_holds():
		return
	var surface: AnimationMixer = mixer()
	if surface != null:
		surface.remove_meta(META_KEY)
