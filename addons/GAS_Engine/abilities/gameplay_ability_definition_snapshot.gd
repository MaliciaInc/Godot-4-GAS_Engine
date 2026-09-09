## A frozen reading of what an ability scene declares, taken once at grant time.
##
## The `PackedScene` stays the one authoring source, but nothing after the
## grant may keep a template Node around to answer it: holding one risks an
## orphan, and instantiating the scene fresh for every cooldown or event-
## routing query is wasted work for a question that does not need a live
## Node at all. This is that answer, captured once and never edited again.
##
## Arrays are copied on capture. A mutation of `per_actor_instance.costs`
## after the grant must not retroactively change what the spec charges.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilityDefinitionSnapshot extends RefCounted

var ability_scene: PackedScene = null
var ability_name: String = ""
var instancing_policy: GameplayAbility.InstancingPolicy = GameplayAbility.InstancingPolicy.PER_ACTOR

## Whether returning from `_activate_ability()` ends the ability, and
## whether activating it again while it runs replaces the activation in
## flight. Frozen with everything else the runtime decides by: an author
## who changed either of these after the grant would be changing what a
## running ability does, from outside it.
var auto_end_on_activate_return: bool = true
var retrigger_while_active: bool = false
var activation_policy: GameplayAbility.ActivationPolicy = GameplayAbility.ActivationPolicy.MANUAL
## The action this grant answers, frozen with everything else it is decided by.
var input_action: StringName = &""

## Where this grant is allowed to run. Frozen with the rest, so what a client
## may ask for is decided at grant time rather than by whatever the scene on
## disk says while a match is in progress.
var net_execution_policy: GameplayAbility.NetExecutionPolicy = (
	GameplayAbility.NetExecutionPolicy.LOCAL_ONLY
)

## Task 15's complete tag semantics - see GameplayAbility for what each means.
var ability_tags: Array[StringName] = []
var activation_required_query: GameplayTagQuery = null
var activation_blocked_query: GameplayTagQuery = null
var activation_owned_tags: Array[StringName] = []
var cancel_abilities_query: GameplayTagQuery = null
var allow_self_cancel: bool = false
var block_abilities_query: GameplayTagQuery = null
## Frozen with the rest: an author who edited these after the grant would be
## changing who is allowed to trigger a running grant, from outside it.
var source_required_query: GameplayTagQuery = null
var source_blocked_query: GameplayTagQuery = null
var target_required_query: GameplayTagQuery = null
var target_blocked_query: GameplayTagQuery = null

## Only consulted for ON_GAMEPLAY_EVENT. See GameplayAbilityEventTrigger.
var gameplay_event_triggers: Array[GameplayAbilityEventTrigger] = []

var costs: Array[GameplayAbilityCost] = []
## The two other ways a price can be written. Frozen with everything else:
## an author who swapped the cost effect after the grant would be changing
## what a running ability charges, from outside it.
var cost_effect: GameplayEffect = null
var custom_costs: Array[GameplayAbilityCustomCost] = []
var cooldown_effect: GameplayEffect = null
var shared_cooldown_effects: Array[GameplayEffect] = []
var shared_cooldown_tags: Array[StringName] = []


## Read a snapshot from a validated probe instance. The probe is only read,
## never mutated or freed by this.
static func _duplicate_resource(value: Resource) -> Resource:
	return value.duplicate(true) if value != null else null


## Every Resource in an untyped array, copied; everything else passed through.
##
## The `as` the strict typing pass will not take is written as an assignment
## after the `is` instead: a cast from Variant is unchecked, and this file is
## depended on by most of the addon, so one unsafe cast here fails to compile a
## hundred other scripts.
static func _duplicate_resource_array(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		if value is Resource:
			var resource: Resource = value
			result.append(resource.duplicate(true))
		else:
			result.append(value)
	return result


static func from_probe(scene: PackedScene, probe: GameplayAbility) -> GameplayAbilityDefinitionSnapshot:
	var snapshot: GameplayAbilityDefinitionSnapshot = GameplayAbilityDefinitionSnapshot.new()
	snapshot.ability_scene = scene
	snapshot.ability_name = probe.ability_name
	snapshot.instancing_policy = probe.instancing_policy
	snapshot.auto_end_on_activate_return = probe.auto_end_on_activate_return
	snapshot.retrigger_while_active = probe.retrigger_while_active
	snapshot.activation_policy = probe.activation_policy
	snapshot.input_action = probe.input_action
	snapshot.net_execution_policy = probe.net_execution_policy
	snapshot.ability_tags = probe.ability_tags.duplicate()
	snapshot.activation_required_query = (
		_duplicate_resource(probe.activation_required_query) as GameplayTagQuery
	)
	snapshot.activation_blocked_query = (
		_duplicate_resource(probe.activation_blocked_query) as GameplayTagQuery
	)
	snapshot.activation_owned_tags = probe.activation_owned_tags.duplicate()
	snapshot.cancel_abilities_query = (
		_duplicate_resource(probe.cancel_abilities_query) as GameplayTagQuery
	)
	snapshot.allow_self_cancel = probe.allow_self_cancel
	snapshot.block_abilities_query = (
		_duplicate_resource(probe.block_abilities_query) as GameplayTagQuery
	)
	snapshot.source_required_query = (
		_duplicate_resource(probe.source_required_query) as GameplayTagQuery
	)
	snapshot.source_blocked_query = (
		_duplicate_resource(probe.source_blocked_query) as GameplayTagQuery
	)
	snapshot.target_required_query = (
		_duplicate_resource(probe.target_required_query) as GameplayTagQuery
	)
	snapshot.target_blocked_query = (
		_duplicate_resource(probe.target_blocked_query) as GameplayTagQuery
	)

	snapshot.gameplay_event_triggers.clear()
	for trigger: GameplayAbilityEventTrigger in probe.gameplay_event_triggers:
		snapshot.gameplay_event_triggers.append(
			_duplicate_resource(trigger) as GameplayAbilityEventTrigger
		)

	snapshot.costs.clear()
	for cost: GameplayAbilityCost in probe.costs:
		snapshot.costs.append(_duplicate_resource(cost) as GameplayAbilityCost)

	snapshot.cost_effect = _duplicate_resource(probe.cost_effect) as GameplayEffect
	snapshot.custom_costs.clear()
	for custom: GameplayAbilityCustomCost in probe.custom_costs:
		snapshot.custom_costs.append(
			_duplicate_resource(custom) as GameplayAbilityCustomCost
		)
	snapshot.cooldown_effect = _duplicate_resource(probe.cooldown_effect) as GameplayEffect

	# One source Resource becomes one duplicate, even when the author listed it
	# twice. "A cooldown listed twice is applied once" is decided by comparing
	# the objects, so two separate copies of one authored effect would start the
	# same cooldown twice - the snapshot has to keep the aliasing it was given,
	# not merely the values.
	var copied_cooldowns: Dictionary[GameplayEffect, GameplayEffect] = {}
	if probe.cooldown_effect != null:
		copied_cooldowns[probe.cooldown_effect] = snapshot.cooldown_effect

	snapshot.shared_cooldown_effects.clear()
	for effect: GameplayEffect in probe.shared_cooldown_effects:
		if effect != null and copied_cooldowns.has(effect):
			snapshot.shared_cooldown_effects.append(copied_cooldowns[effect])
			continue
		var copy: GameplayEffect = _duplicate_resource(effect) as GameplayEffect
		if effect != null:
			copied_cooldowns[effect] = copy
		snapshot.shared_cooldown_effects.append(copy)
	snapshot.shared_cooldown_tags = probe.shared_cooldown_tags.duplicate()
	return snapshot

#: Every field this snapshot copies off the probe, and therefore every field a
#: running instance can be given a value the engine will never read.
#:
#: Declared once and used both to report drift and to test that the list has not
#: fallen behind `from_probe()`. A hand-kept list that silently stops matching
#: what is captured would put the check back in the state it exists to prevent.
const CAPTURED_FIELDS: Array[StringName] = [
	&"ability_name",
	&"instancing_policy",
	&"auto_end_on_activate_return",
	&"retrigger_while_active",
	&"activation_policy",
	&"input_action",
	GameplayAbility.NET_EXECUTION_POLICY_FIELD,
	&"ability_tags",
	&"activation_required_query",
	&"activation_blocked_query",
	&"activation_owned_tags",
	&"cancel_abilities_query",
	&"allow_self_cancel",
	&"block_abilities_query",
	&"source_required_query",
	&"source_blocked_query",
	&"target_required_query",
	&"target_blocked_query",
	&"gameplay_event_triggers",
	&"costs",
	&"cost_effect",
	&"custom_costs",
	&"cooldown_effect",
	&"shared_cooldown_effects",
	&"shared_cooldown_tags",
]


## Report an instance whose authoring no longer matches what the engine reads.
##
## Capturing on grant is deliberate: a definition free to drift afterwards would
## let two battlers holding the same ability disagree about what it does. What
## was not deliberate is the silence around it. A value assigned to a running
## instance is ignored, so an ability whose cost never arrived is simply free,
## an ability whose cooldown never arrived has none - and a clean log looks
## exactly like a correct one. A real game shipped a free ability for a whole
## session before a screenshot caught it.
##
## Lives here rather than on GameplayAbility because this is the class that did
## the freezing and already documents it; the ability only knows it was frozen.
##
## Returns whether it reported, so the caller can say it once per instance - the
## mistake is a wiring one, and repeating it every commit buries the first report
## under the hundredth.
static func report_drift(
	ability: GameplayAbility, definition: GameplayAbilityDefinitionSnapshot
) -> bool:
	if definition == null:
		return false

	var drifted: Array[String] = []
	for field: StringName in CAPTURED_FIELDS:
		if not _same(ability.get(field), definition.get(field)):
			drifted.append(String(field))
	if drifted.is_empty():
		return false

	# Parenthesised before the format: `%` binds tighter than `+`, so without it
	# the arguments reach only the last fragment and every placeholder before it
	# survives into the message as literal text.
	var template: String = (
		"GAS_Engine: ability '%s' was given %s after it was granted, and the engine "
		+ "will not read %s. Its definition was captured at the grant and is what "
		+ "every later decision prices, gates and times from. Set these before the "
		+ "grant - an exported property's setter runs early enough, `_ready()` does "
		+ "not."
	)
	var message: String = template % [
		ability.ability_name if ability.ability_name != "" else ability.name,
		", ".join(drifted),
		"them" if drifted.size() > 1 else "it",
	]
	# One channel, not two. A signal beside this would be a second way to learn
	# the same thing, and the engine's own error channel is where a wiring
	# mistake belongs - it reaches a game that wired up nothing at all.
	push_error(message)
	return true


## Equal for this purpose: the snapshot holds the very same resources and
## duplicated arrays, so anything that still matches is the same objects in the
## same order. Compared by identity rather than by value, because two arrays
## that happen to hold equal numbers are still two authorings, and the engine
## reads only one of them.
static func _same(mine: Variant, theirs: Variant) -> bool:
	if mine == null or theirs == null:
		return mine == theirs

	if mine is Array and theirs is Array:
		var a: Array = mine
		var b: Array = theirs
		if a.size() != b.size():
			return false
		for index: int in a.size():
			if not _same(a[index], b[index]):
				return false
		return true

	if mine is Dictionary and theirs is Dictionary:
		var a_dict: Dictionary = mine
		var b_dict: Dictionary = theirs
		if a_dict.size() != b_dict.size():
			return false
		for key: Variant in a_dict:
			if not b_dict.has(key) or not _same(a_dict[key], b_dict[key]):
				return false
		return true

	if mine is Resource and theirs is Resource:
		var a_resource: Resource = mine
		var b_resource: Resource = theirs
		if a_resource.get_script() != b_resource.get_script():
			return false
		for property: Dictionary in a_resource.get_property_list():
			var usage: int = property.get("usage", 0)
			if (usage & PROPERTY_USAGE_STORAGE) == 0:
				continue
			var name: StringName = property.get("name", &"")
			if name == &"resource_path" or name == &"resource_name":
				continue
			if not _same(a_resource.get(name), b_resource.get(name)):
				return false
		return true

	if mine is float and theirs is float:
		var a_float: float = mine
		var b_float: float = theirs
		# NaN is not equal to itself, and a copy of a NaN is still the value the
		# author wrote. Without this, an ability whose cost is deliberately NaN -
		# there are tests for exactly that, because the engine has to refuse it -
		# is reported as having drifted from a definition nobody touched.
		if is_nan(a_float) and is_nan(b_float):
			return true
		return a_float == b_float

	return mine == theirs
