## Which run of an ability, as opposed to which ability.
##
## An ability is granted once and activated many times, and almost everything a
## message says is about one of those runs rather than about the grant: this
## cast was confirmed, this cast was refused, this cast's animation was
## interrupted. Saying "the fireball" is not enough to answer any of them when a
## character can have two fireballs in the air.
##
## Whose entity, and which run of it. Both, because a sequence number alone
## collides across characters the moment two of them cast at once, and each
## machine counts its own.
##
## The sequence is `GameplayAbility.activation_id` - the same number the
## animation ownership receipt carries - so the local half of the engine and the
## networked half are talking about the same run rather than two numberings that
## have to be kept in step.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetActivationId extends RefCounted

const NONE: int = 0

var entity: GameplayNetEntityId = null
var sequence: int = NONE


static func of(for_entity: GameplayNetEntityId, run: int) -> GameplayNetActivationId:
	var made: GameplayNetActivationId = GameplayNetActivationId.new()
	made.entity = for_entity
	made.sequence = run
	return made


## Valid only when both halves are: a run number with nobody running it names
## nothing, and an entity with no run is the entity, not one of its casts.
func is_valid() -> bool:
	return sequence != NONE and entity != null and entity.is_valid()


func same_as(other: GameplayNetActivationId) -> bool:
	if other == null or not is_valid():
		return false
	return other.sequence == sequence and entity.same_as(other.entity)


## Two ints, in the order the reader of a wire dump would want them.
func to_wire() -> PackedInt64Array:
	return PackedInt64Array([entity.to_wire() if entity != null else 0, sequence])


static func from_wire(wire: PackedInt64Array) -> GameplayNetActivationId:
	if wire.size() != 2:
		return GameplayNetActivationId.new()
	return GameplayNetActivationId.of(GameplayNetEntityId.from_wire(wire[0]), wire[1])
