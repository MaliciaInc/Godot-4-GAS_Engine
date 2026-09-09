## One entity's ability system as it stood at one moment, however it was
## reached.
##
## The distinction this whole file rests on: an ASC selected in a scene being
## edited is a Resource on disk, and an ASC in a running game is a thing with
## tags on it, effects ticking and abilities half way through. Confusing the two
## is how a debugger comes to show somebody the ability's authored level while
## they are watching it be levelled up in front of them.
##
## So this is out of date the moment it exists, which is a property of a
## snapshot and is why it is called one.
##
## Two ways in and one shape. `of()` takes it from a live component, for the
## overlay the game draws itself; `from_message()` rebuilds it from what the
## running game sent across the remote-debug channel, for the editor's panel.
## There used to be a class for each, with the same four inner types spelled
## twice - and two descriptions of one thing disagree the first time one of them
## learns about a field the other does not have.
##
## Under `debug/` rather than `editor/` because a running game draws from it,
## and nothing a running game names may live in the editor's half.
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

	## Whether nothing holds this tag directly - a parent that exists only
	## because something under it does.
	func is_a_family_only() -> bool:
		return count == 0 and family_count > 0


## One grant, by its handle - which is what a grant is. The instance behind it
## comes and goes with each activation.
class Ability extends RefCounted:
	var handle: int = 0
	var name: String = ""
	var level: float = 1.0
	var active: int = 0

	## The three ordinary reasons an ability is not going off, which look
	## identical from outside: it is on cooldown, it is already running, or the
	## last attempt was refused for a reason nobody was listening for.
	var on_cooldown: bool = false
	var cooldown_seconds_left: float = 0.0
	var cooldown_turns_left: int = 0

	## What its most recent try_activate() said, named rather than numbered.
	## Empty when it has never been tried.
	var last_result: String = ""

	func is_running() -> bool:
		return active > 0


class Effect extends RefCounted:
	var handle: int = 0
	var name: String = ""
	var stacks: int = 1
	var seconds_left: float = 0.0
	var turns_left: int = 0

	## Applied but not in force. The state somebody stares at longest: the stun
	## they can see in the list that is not stunning anybody.
	var inhibited: bool = false


## The instance id the game reported. An id, not a reference: when this came
## over the wire, the object is in another process.
var asc_id: int = 0

## Who it belongs to and who it happens to, which F5.2.1 made two answers.
var owner_name: String = ""
var avatar_name: String = ""

var attributes: Array[Attribute] = []
var tags: Array[Tag] = []
var abilities: Array[Ability] = []
var effects: Array[Effect] = []

## The recent attribute changes, when a history was kept. Newest first, and
## empty for a snapshot that came over the wire - the channel sends state, and
## a history is the watching game's own.
var changes: Array[GasAttributeHistory.Change] = []


#region Taken from a live component
## Take one, from a component in this process.
##
## Nothing here reads back into the component while it is being drawn: a
## snapshot that asked the runtime a question mid-draw would be a debugger
## changing what it is debugging.
##
## A history is optional because keeping one costs a connection and a hundred
## and twenty-eight entries per target, and a game showing only current state
## should not pay for it.
static func of(
	component: AbilitySystemComponent, history: GasAttributeHistory = null
) -> GasRuntimeSnapshot:
	var taken: GasRuntimeSnapshot = GasRuntimeSnapshot.new()
	if component == null or not is_instance_valid(component):
		return taken

	taken.asc_id = component.get_instance_id()
	taken.owner_name = _named(component.get_parent())
	taken.avatar_name = _named(component.get_effect_target())
	taken.attributes = _attributes_of(component)
	taken.tags = _tags_of(component)
	taken.effects = _effects_of(component)
	taken.abilities = _abilities_of(component)
	if history != null:
		taken.changes = history.recent()
	return taken


static func _named(node: Node) -> String:
	return String(node.name) if node != null and is_instance_valid(node) else ""


static func _attributes_of(component: AbilitySystemComponent) -> Array[Attribute]:
	var found: Array[Attribute] = []
	for attribute_name: StringName in component.attributes.all_attribute_names():
		var one: Attribute = Attribute.new()
		one.name = String(attribute_name)
		one.base = component.get_attribute_base(attribute_name)
		one.current = component.get_attribute_current(attribute_name)
		found.append(one)
	return found


## Every tag held, and every ancestor of one.
##
## A parent nothing holds directly is still something a listener watches, and a
## debugger that only listed what is written on the entity would leave the
## person to work out that `State` is held at all.
static func _tags_of(component: AbilitySystemComponent) -> Array[Tag]:
	var found: Array[Tag] = []
	var families: Array[StringName] = []
	for tag: StringName in component.tags.active_tags():
		found.append(_tag_row(component, tag))
		for ancestor: StringName in GameplayTagRuntime.ancestors_of(tag):
			if ancestor != tag and not families.has(ancestor):
				families.append(ancestor)

	for ancestor: StringName in families:
		found.append(_tag_row(component, ancestor))
	return found


static func _tag_row(component: AbilitySystemComponent, tag: StringName) -> Tag:
	var one: Tag = Tag.new()
	one.name = String(tag)
	one.count = component.tags.count_exact(tag)
	one.family_count = component.tags.count(tag)
	return one


static func _effects_of(component: AbilitySystemComponent) -> Array[Effect]:
	var found: Array[Effect] = []
	for active: ActiveGameplayEffect in component.get_active_effects():
		var one: Effect = Effect.new()
		one.handle = active.handle.id if active.handle != null else 0
		one.name = String(active.get_effect_def().resource_name)
		one.stacks = active.stack_count
		one.seconds_left = active.time_remaining
		one.turns_left = component.get_effect_turns_remaining(active.handle)
		one.inhibited = active.inhibited
		found.append(one)
	return found


static func _abilities_of(component: AbilitySystemComponent) -> Array[Ability]:
	var found: Array[Ability] = []
	for spec: GameplayAbilitySpec in component.get_ability_specs():
		var one: Ability = Ability.new()
		one.handle = spec.handle.id
		one.name = String(spec.definition.ability_name)
		one.level = spec.level
		one.active = spec.active_count

		var cooldown: AbilityCooldownState = component.get_ability_cooldown_state(spec.handle)
		if cooldown != null:
			one.on_cooldown = cooldown.active
			one.cooldown_seconds_left = cooldown.seconds_remaining
			one.cooldown_turns_left = cooldown.turns_remaining

		# Why it did not go off, kept on the spec by the runtime for exactly
		# this: answering it without a listener that was already connected at
		# the moment it failed.
		if spec.last_activation_result != null:
			one.last_result = GasDebugMessage.key_of(
				GameplayAbilityActivationResult.Status.keys(),
				int(spec.last_activation_result.status)
			)
		found.append(one)
	return found
#endregion


#region Rebuilt from what the game sent
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
		made.abilities.append(_ability_from(entry))

	for entry: Dictionary in said.get(GasDebugMessage.EFFECTS, []):
		var effect: Effect = Effect.new()
		effect.handle = entry.get(GasDebugMessage.HANDLE, 0)
		effect.name = entry.get(GasDebugMessage.NAME, "")
		effect.stacks = entry.get(GasDebugMessage.STACKS, 1)
		effect.seconds_left = entry.get(GasDebugMessage.SECONDS_LEFT, 0.0)
		effect.turns_left = entry.get(GasDebugMessage.TURNS_LEFT, 0)
		effect.inhibited = entry.get(GasDebugMessage.INHIBITED, false)
		made.effects.append(effect)

	return made


static func _ability_from(entry: Dictionary) -> Ability:
	var ability: Ability = Ability.new()
	ability.handle = entry.get(GasDebugMessage.HANDLE, 0)
	ability.name = entry.get(GasDebugMessage.NAME, "")
	ability.level = entry.get(GasDebugMessage.LEVEL, 1.0)
	ability.active = entry.get(GasDebugMessage.ACTIVE, 0)
	ability.on_cooldown = entry.get(GasDebugMessage.ON_COOLDOWN, false)
	ability.cooldown_seconds_left = entry.get(GasDebugMessage.COOLDOWN_SECONDS_LEFT, 0.0)
	ability.cooldown_turns_left = entry.get(GasDebugMessage.COOLDOWN_TURNS_LEFT, 0)
	ability.last_result = entry.get(GasDebugMessage.LAST_RESULT, "")
	return ability
#endregion


#region Finding one of them
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
#endregion
