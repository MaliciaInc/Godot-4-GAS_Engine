## An aim that answers with a place rather than with somebody.
##
## Two providers are this: one works the spot out from a ray and one is told the
## spot. What they share is everything after that - the answer is one location,
## never an actor, and it has to be somewhere this caster could reach - and that
## shared part is here so there is one rule about it rather than two that drift.
##
## Not a second provider base. It is a GameplayTargetProvider like every other,
## and it exists for the same reason any subclass does: two things that are the
## same kind of thing.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayLocationProvider3D extends GameplayTargetProvider

## How far from the caster the spot may be. Zero means anywhere, which is what
## an aim with no range restriction is.
var max_range: float = 0.0


## What a machine that was not there for the aiming can still refuse.
##
## Three things, and all three are about this provider's own numbers: the claim
## names nobody, because an aim that answers with a place never produced an
## actor; it names exactly one place, because that is what one of these aims is;
## and the place is inside the range this provider enforces.
##
## Not everything. A client claiming a spot that was legal a frame ago is a
## question about time, and nothing here can answer it.
func validate_authoritative(
	data: GameplayAbilityTargetData, checking_asc: AbilitySystemComponent
) -> bool:
	if data == null or checking_asc == null:
		return false
	if not data.get_target_nodes().is_empty():
		return false
	var places: Array[GameplayTargetHit] = data.get_all_hits()
	if places.size() != 1 or not places[0].has_position:
		return false
	return within_range(places[0].position_3d)


## Whether a spot is somewhere this caster could have aimed at.
##
## Answers true with no avatar rather than refusing: a provider on a component
## that has no body yet is being asked a question about a distance from nothing,
## and refusing every aim would be a worse answer than allowing them.
func within_range(spot: Vector3) -> bool:
	if max_range <= 0.0:
		return true
	var from: Node3D = avatar() as Node3D
	if from == null:
		return true
	return from.global_position.distance_to(spot) <= max_range
