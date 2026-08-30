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

## Fields the ability model has not yet formalised past Phase 2. Named
## `legacy_*` so a later task's real replacement is unambiguous about which
## field it retires.
var legacy_ability_tag: StringName = &""
var legacy_activation_blocked_tags: Array[StringName] = []
var legacy_activation_required_tags: Array[StringName] = []
var legacy_trigger_event_tag: StringName = &""

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
	snapshot.legacy_ability_tag = probe.ability_tag
	snapshot.legacy_activation_blocked_tags = probe.activation_blocked_tags.duplicate()
	snapshot.legacy_activation_required_tags = probe.activation_required_tags.duplicate()
	snapshot.legacy_trigger_event_tag = probe.trigger_event_tag
	snapshot.costs = probe.costs.duplicate()
	snapshot.cooldown_effect = probe.cooldown_effect
	snapshot.shared_cooldown_effects = probe.shared_cooldown_effects.duplicate()
	snapshot.shared_cooldown_tags = probe.shared_cooldown_tags.duplicate()
	return snapshot
