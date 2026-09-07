## One entity of the running game, as it stood when the game was asked.
##
## The distinction this whole file rests on: an ASC selected in a scene being
## edited is a Resource on disk, and an ASC in a running game is a thing with
## tags on it, effects ticking and abilities half way through. Confusing the two
## is how a debugger comes to show somebody the ability's authored level while
## they are watching it be levelled up in front of them.
##
## So none of this is read from anything. It is what the game said, when it said
## it, and it is out of date the moment it arrives - which is a property of a
## snapshot and is why it is called one.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasRuntimeSnapshot extends RefCounted

## One attribute, at both of its values.
##
## Both, because they answer different questions: the base is what the entity
## durably is and the current is what it is worth right now with everything
## active on it, and a debugger showing one of them is a debugger somebody has
## to guess in front of.
class Attribute extends RefCounted:
	var name: String = ""
	var base: float = 0.0
	var current: float = 0.0


## One tag, at both of its counts.
##
## `count` is how many effects grant this exact tag; `family_count` is how many
## grant it or anything under it. `State` is held twice by a stun and a root
## while nothing holds `State` itself, and a debugger showing one number would
## have somebody working the other out by hand.
class Tag extends RefCounted:
	var name: String = ""
	var count: int = 0
	var family_count: int = 0


## One grant, by its handle - which is what a grant is. The instance behind it
## comes and goes with each activation.
class Ability extends RefCounted:
	var handle: int = 0
	var name: String = ""
	var level: float = 1.0
	var active: int = 0


class Effect extends RefCounted:
	var handle: int = 0
	var name: String = ""
	var stacks: int = 1
	var seconds_left: float = 0.0
	var turns_left: int = 0


## The instance id the game reported. An id, not a reference: the object is in
## another process.
var asc_id: int = 0

## Who it belongs to and who it happens to, which F5.2.1 made two answers.
var owner_name: String = ""
var avatar_name: String = ""

var attributes: Array[Attribute] = []
var tags: Array[Tag] = []
var abilities: Array[Ability] = []
var effects: Array[Effect] = []


## The snapshot a message describes, or null when it describes none.
static func from_message(said: Dictionary) -> GasRuntimeSnapshot:
	if not said.has(GasDebugMessage.ASC_ID):
		return null

	var made: GasRuntimeSnapshot = GasRuntimeSnapshot.new()
	made.asc_id = said[GasDebugMessage.ASC_ID]
	made.owner_name = said.get(GasDebugMessage.OWNER, "")
	made.avatar_name = said.get(GasDebugMessage.AVATAR, "")

	for entry: Dictionary in said.get(GasDebugMessage.ATTRIBUTES, []):
		var attribute: Attribute = Attribute.new()
		attribute.name = entry.get(GasDebugMessage.NAME, "")
		attribute.base = entry.get(GasDebugMessage.BASE, 0.0)
		attribute.current = entry.get(GasDebugMessage.CURRENT, 0.0)
		made.attributes.append(attribute)

	for entry: Dictionary in said.get(GasDebugMessage.TAGS, []):
		var tag: Tag = Tag.new()
		tag.name = entry.get(GasDebugMessage.NAME, "")
		tag.count = entry.get(GasDebugMessage.COUNT, 0)
		tag.family_count = entry.get(GasDebugMessage.FAMILY_COUNT, 0)
		made.tags.append(tag)

	for entry: Dictionary in said.get(GasDebugMessage.ABILITIES, []):
		var ability: Ability = Ability.new()
		ability.handle = entry.get(GasDebugMessage.HANDLE, 0)
		ability.name = entry.get(GasDebugMessage.NAME, "")
		ability.level = entry.get(GasDebugMessage.LEVEL, 1.0)
		ability.active = entry.get(GasDebugMessage.ACTIVE, 0)
		made.abilities.append(ability)

	for entry: Dictionary in said.get(GasDebugMessage.EFFECTS, []):
		var effect: Effect = Effect.new()
		effect.handle = entry.get(GasDebugMessage.HANDLE, 0)
		effect.name = entry.get(GasDebugMessage.NAME, "")
		effect.stacks = entry.get(GasDebugMessage.STACKS, 1)
		effect.seconds_left = entry.get(GasDebugMessage.SECONDS_LEFT, 0.0)
		effect.turns_left = entry.get(GasDebugMessage.TURNS_LEFT, 0)
		made.effects.append(effect)

	return made


## The attribute of that name, or null. By name because that is what a person
## types into a filter.
func attribute(named: String) -> Attribute:
	for found: Attribute in attributes:
		if found.name == named:
			return found
	return null


## The grant that handle names, or null when this entity has no such grant.
func ability(handle: int) -> Ability:
	for found: Ability in abilities:
		if found.handle == handle:
			return found
	return null


func effect(handle: int) -> Effect:
	for found: Effect in effects:
		if found.handle == handle:
			return found
	return null
