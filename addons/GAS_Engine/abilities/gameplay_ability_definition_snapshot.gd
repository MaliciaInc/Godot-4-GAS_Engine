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
## @meta_license: MIT
class_name GameplayAbilityDefinitionSnapshot extends RefCounted

var ability_scene: PackedScene = null
var ability_name: String = ""
var instancing_policy: GameplayAbility.InstancingPolicy = GameplayAbility.InstancingPolicy.PER_ACTOR
var activation_policy: GameplayAbility.ActivationPolicy = GameplayAbility.ActivationPolicy.MANUAL

## Task 15's complete tag semantics - see GameplayAbility for what each means.
var ability_tags: Array[StringName] = []
var activation_required_query: GameplayTagQuery = null
var activation_blocked_query: GameplayTagQuery = null
var activation_owned_tags: Array[StringName] = []
var cancel_abilities_query: GameplayTagQuery = null
var allow_self_cancel: bool = false
var block_abilities_query: GameplayTagQuery = null
var target_required_query: GameplayTagQuery = null
var target_blocked_query: GameplayTagQuery = null

## Only consulted for ON_GAMEPLAY_EVENT. See GameplayAbilityEventTrigger.
var gameplay_event_triggers: Array[GameplayAbilityEventTrigger] = []

var costs: Array[GameplayAbilityCost] = []
var cooldown_effect: GameplayEffect = null
var shared_cooldown_effects: Array[GameplayEffect] = []
var shared_cooldown_tags: Array[StringName] = []


## Read a snapshot from a validated probe instance. The probe is only read,
## never mutated or freed by this.
static func from_probe(scene: PackedScene, probe: GameplayAbility) -> GameplayAbilityDefinitionSnapshot:
	var snapshot: GameplayAbilityDefinitionSnapshot = GameplayAbilityDefinitionSnapshot.new()
	snapshot.ability_scene = scene
	snapshot.ability_name = probe.ability_name
	snapshot.instancing_policy = probe.instancing_policy
	snapshot.activation_policy = probe.activation_policy
	snapshot.ability_tags = probe.ability_tags.duplicate()
	snapshot.activation_required_query = probe.activation_required_query
	snapshot.activation_blocked_query = probe.activation_blocked_query
	snapshot.activation_owned_tags = probe.activation_owned_tags.duplicate()
	snapshot.cancel_abilities_query = probe.cancel_abilities_query
	snapshot.allow_self_cancel = probe.allow_self_cancel
	snapshot.block_abilities_query = probe.block_abilities_query
	snapshot.target_required_query = probe.target_required_query
	snapshot.target_blocked_query = probe.target_blocked_query
	snapshot.gameplay_event_triggers = probe.gameplay_event_triggers.duplicate()
	snapshot.costs = probe.costs.duplicate()
	snapshot.cooldown_effect = probe.cooldown_effect
	snapshot.shared_cooldown_effects = probe.shared_cooldown_effects.duplicate()
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
	&"activation_policy",
	&"ability_tags",
	&"activation_required_query",
	&"activation_blocked_query",
	&"activation_owned_tags",
	&"cancel_abilities_query",
	&"allow_self_cancel",
	&"block_abilities_query",
	&"target_required_query",
	&"target_blocked_query",
	&"gameplay_event_triggers",
	&"costs",
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
	if mine is Array and theirs is Array:
		var a: Array = mine
		var b: Array = theirs
		if a.size() != b.size():
			return false
		for index: int in a.size():
			if a[index] != b[index]:
				return false
		return true
	return mine == theirs
