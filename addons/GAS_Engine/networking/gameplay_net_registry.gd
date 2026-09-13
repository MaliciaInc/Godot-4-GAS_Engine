## The two tables that turn a name into a thing, and back.
##
## A message names an entity and a definition. This machine has an
## AbilitySystemComponent and a Resource. Neither pair is derivable from the
## other - that is the whole reason net ids exist - so the mapping is a table
## somebody fills in, and this is it.
##
## Entities are registered by whoever knows: the authority assigns the id and
## every peer registers its own node under the id it was told. Definitions
## register themselves, because their id is derived from where they live, but
## they are still registered rather than trusted: a hash collides, and two
## abilities answering one id is a thing to refuse at start-up rather than
## discover when the wrong one activates.
##
## Ownership lives here too, next to what it is about. Which peer owns an
## entity is the question every authority rule ends up asking, and an answer
## kept somewhere else is an answer that can disagree with the entity table it
## is about.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetRegistry extends RefCounted

const NO_PEER: int = -1

## What an entity registered without an opinion is: whatever the runtime says.
##
## Its own value rather than one of the modes, because "no opinion" and "MIXED"
## are different things - an entity that asked for MIXED keeps it when the
## runtime's default changes, and one that asked for nothing follows.
const RUNTIME_DEFAULT: int = -1

const COLLISION: String = (
	"GAS_Engine: net definition id %d is claimed by both %s and %s. "
	+ "Rename one of them: two definitions answering one id is one of them "
	+ "activating in place of the other."
)

## Keyed by the id's value rather than by the id object, because two ids for
## one entity are two objects and a dictionary would keep both.
var _asc_by_entity: Dictionary[int, AbilitySystemComponent] = {}

## Keyed by the component itself rather than by its ObjectID, which is
## the id nothing in this folder is allowed to name. A local table wanting
## a local key does not need one: the object is the key.
var _entity_by_asc: Dictionary[AbilitySystemComponent, int] = {}
var _owner_by_entity: Dictionary[int, int] = {}

## How much is said about one entity, for the ones that asked for something
## other than the runtime's default. Absent means no opinion.
var _mode_by_entity: Dictionary[int, int] = {}
var _definition_by_id: Dictionary[int, Resource] = {}

## What a local effect handle is called on the wire.
##
## Mapped and not converted, which is the difference the phase draws: a
## handle names an application in one process, this names it on every
## machine that heard about it, and a number counted here is the one thing
## that can be both. Keyed by the handle object because a local table wanting
## a local key already has one.
var _net_effect_by_handle: Dictionary[GameplayEffectHandle, int] = {}
var _effects_named: int = 0


#region Entities
## Put a component under an id, owned by a peer.
##
## Refuses an id that already names a different component, and refuses a
## component that already answers to a different id - both directions of the
## same bijection, and a hand-maintained check could only ever see the first
## of them: nothing before this read `_entity_by_asc` back, so a second id for
## one ASC quietly took over half the mapping and left the other half stale.
## An entity told about is either both tables agreeing, or neither is written.
##
## Re-registering the same pair is not a refusal - a peer told twice about an
## entity it already has is an ordinary thing on a network, and treating it as
## an error would make every retransmission an error - but only when what is
## being said about it has not changed. An owner or a replication mode that
## has is a transfer, not a retransmission, and a transfer goes through
## `set_owner()` or `set_replication_mode()`, which is where a caller that
## meant one finds out whether it happened rather than having it happen
## silently inside a call that looks like a repeat.
func register_entity(
	id: GameplayNetEntityId,
	asc: AbilitySystemComponent,
	owner_peer: int = NO_PEER,
	replication_mode: int = RUNTIME_DEFAULT
) -> bool:
	if id == null or not id.is_valid() or asc == null:
		return false
	var taken: AbilitySystemComponent = _asc_by_entity.get(id.value)
	if taken != null and taken != asc:
		return false
	var named: Variant = _entity_by_asc.get(asc)
	if named != null and int(named) != id.value:
		return false
	if taken == asc:
		if owner_of(id) != owner_peer:
			return false
		if replication_mode != RUNTIME_DEFAULT and _mode_by_entity.get(id.value, RUNTIME_DEFAULT) != replication_mode:
			return false

	_asc_by_entity[id.value] = asc
	_entity_by_asc[asc] = id.value
	_owner_by_entity[id.value] = owner_peer
	if replication_mode != RUNTIME_DEFAULT:
		_mode_by_entity[id.value] = replication_mode
	return true


## Change who owns an entity already registered here. False for an id nobody
## registered: setting ownership on an entity that names nothing is a mistake
## worth learning about, the same reason `set_replication_mode` refuses one.
func set_owner(id: GameplayNetEntityId, new_owner_peer: int) -> bool:
	if id == null or not _asc_by_entity.has(id.value):
		return false
	_owner_by_entity[id.value] = new_owner_peer
	return true


#region How much is said about one entity
## Say how much to replicate about this entity, whatever the runtime's default.
##
## A boss whose every attribute matters and a crowd of villagers whose health
## bar is the whole of what anybody sees are two different amounts of network,
## and a runtime with one setting makes a game choose the expensive one for
## everybody. False for an entity nobody registered: setting a mode on an id
## that names nothing is a mistake worth learning about.
func set_replication_mode(
	id: GameplayNetEntityId, mode: GameplayNetReplication.Mode
) -> bool:
	if id == null or not _asc_by_entity.has(id.value):
		return false
	_mode_by_entity[id.value] = int(mode)
	return true


## How much is said about this entity, or `fallback` when it has no say of its
## own.
##
## The fallback is handed in rather than read from a runtime: this registry
## knows what each entity asked for and nothing about whose default it is.
func replication_mode_for(
	id: GameplayNetEntityId, fallback: GameplayNetReplication.Mode
) -> GameplayNetReplication.Mode:
	if id == null or not _mode_by_entity.has(id.value):
		return fallback
	return _mode_by_entity[id.value] as GameplayNetReplication.Mode


## Forget what this entity asked for, so it follows the runtime again.
func clear_replication_mode(id: GameplayNetEntityId) -> bool:
	if id == null or not _mode_by_entity.has(id.value):
		return false
	_mode_by_entity.erase(id.value)
	return true
#endregion


## Forget everything this registry itself knows about an entity: which
## component it names, who owns it, and how much is said about it. Reused
## under the same id afterward, the next occupant starts from nothing rather
## than inheriting an opinion this registry formed about whoever had it before.
func forget_entity(id: GameplayNetEntityId) -> void:
	if id == null or not _asc_by_entity.has(id.value):
		return
	var asc: AbilitySystemComponent = _asc_by_entity[id.value]
	_asc_by_entity.erase(id.value)
	_owner_by_entity.erase(id.value)
	_mode_by_entity.erase(id.value)
	if asc != null:
		_entity_by_asc.erase(asc)


## Every component this registry currently names, for a runtime tearing itself
## down that has to tell each one it is no longer theirs.
func registered_ascs() -> Array[AbilitySystemComponent]:
	var found: Array[AbilitySystemComponent] = []
	for asc: AbilitySystemComponent in _asc_by_entity.values():
		found.append(asc)
	return found


## The component an id names here, or null when this machine has none.
##
## Null is an ordinary answer, not a failure: a client is told about entities
## it has not spawned yet, and a message about one it does not have is a
## message to drop rather than to act on halfway.
func asc_for(id: GameplayNetEntityId) -> AbilitySystemComponent:
	if id == null or not id.is_valid():
		return null
	var found: AbilitySystemComponent = _asc_by_entity.get(id.value)
	return found if is_instance_valid(found) else null


func entity_for(asc: AbilitySystemComponent) -> GameplayNetEntityId:
	if asc == null or not _entity_by_asc.has(asc):
		return GameplayNetEntityId.new()
	return GameplayNetEntityId.of(_entity_by_asc[asc])


## Which peer owns an entity, or NO_PEER when nobody does.
##
## An entity nobody owns is ordinary - a monster, a door, anything the
## authority drives - and it is not the same as an entity owned by peer zero.
func owner_of(id: GameplayNetEntityId) -> int:
	if id == null or not _owner_by_entity.has(id.value):
		return NO_PEER
	return _owner_by_entity[id.value]


func is_owned_by(id: GameplayNetEntityId, by_peer: int) -> bool:
	return by_peer != NO_PEER and owner_of(id) == by_peer


func entity_count() -> int:
	return _asc_by_entity.size()
#endregion


#region Definitions
## Register a definition and hand back the id both machines will call it.
##
## Refuses a collision rather than overwriting: two definitions answering one
## id is one of them activating in place of the other, and that is a thing to
## find out about at start-up with both names in hand.
func register_definition(definition: Resource) -> GameplayNetDefinitionId:
	var id: GameplayNetDefinitionId = GameplayNetDefinitionId.of_resource(definition)
	if not id.is_valid():
		return id

	var taken: Resource = _definition_by_id.get(id.value)
	if taken != null and taken.resource_path != definition.resource_path:
		push_error(COLLISION % [id.value, taken.resource_path, definition.resource_path])
		return GameplayNetDefinitionId.new()

	_definition_by_id[id.value] = definition
	return id


## What an id names here, or null when this machine has not registered it.
func definition_for(id: GameplayNetDefinitionId) -> Resource:
	if id == null or not id.is_valid():
		return null
	var found: Resource = _definition_by_id.get(id.value)
	return found


func definition_count() -> int:
	return _definition_by_id.size()


## The wire name for a local effect handle, assigned the first time it is
## asked for and the same one every time after.
##
## Counted rather than derived. There is nothing about an application to
## derive a stable number from - it is one moment on one machine - so the
## authority counts and everyone else is told, which is the same shape the
## entity ids have and for the same reason.
func net_effect_id(handle: GameplayEffectHandle) -> int:
	if handle == null:
		return GameplayNetEffectState.NONE
	if _net_effect_by_handle.has(handle):
		return _net_effect_by_handle[handle]
	_effects_named += 1
	_net_effect_by_handle[handle] = _effects_named
	return _effects_named
#endregion


## Let go of everything, for a runtime being torn down.
##
## A registry holding components is a registry keeping a whole scene's worth of
## nodes reachable, which is the leak this addon has already had once.
func clear() -> void:
	_asc_by_entity.clear()
	_entity_by_asc.clear()
	_owner_by_entity.clear()
	_definition_by_id.clear()
	_net_effect_by_handle.clear()
