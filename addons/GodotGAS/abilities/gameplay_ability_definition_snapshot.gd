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
## @meta_addon: GodotGAS, Arhalies fork
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
