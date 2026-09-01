## A read-only picture of one granted ability spec, for the runtime debugger.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GasAbilitySnapshot extends RefCounted

var handle: GameplayAbilityHandle = null
var definition: GameplayAbilityDefinitionSnapshot = null
var level: float = 1.0
var input_id: int = -1
var source: GameplayAbilitySource = null
var instancing_policy: GameplayAbility.InstancingPolicy = GameplayAbility.InstancingPolicy.PER_ACTOR
var activation_policy: GameplayAbility.ActivationPolicy = GameplayAbility.ActivationPolicy.MANUAL
var active_count: int = 0
var effective_tags: Array[StringName] = []
var pending_remove: bool = false
var cooldown: AbilityCooldownState = null
## What try_activate() answered the last time this spec attempted to
## activate - null before the first attempt. See
## GameplayAbilitySpec.last_activation_result.
var last_activation_result: GameplayAbilityActivationResult = null
## The Node(s) actually running this spec right now - always at most one
## for PER_ACTOR, any number for PER_EXECUTION.
var active_instances: Array[GameplayAbility] = []


static func capture_all(asc: AbilitySystemComponent) -> Array[GasAbilitySnapshot]:
	var snapshots: Array[GasAbilitySnapshot] = []
	if asc == null:
		return snapshots
	for spec: GameplayAbilitySpec in asc.ability_runtime.specs():
		snapshots.append(_capture_one(asc, spec))
	return snapshots


static func _capture_one(asc: AbilitySystemComponent, spec: GameplayAbilitySpec) -> GasAbilitySnapshot:
	var snapshot: GasAbilitySnapshot = GasAbilitySnapshot.new()
	snapshot.handle = spec.handle
	snapshot.definition = spec.definition
	snapshot.level = spec.level
	snapshot.input_id = spec.input_id
	snapshot.source = spec.source
	snapshot.active_count = spec.active_count
	snapshot.pending_remove = spec.pending_remove
	snapshot.effective_tags = AbilityRuntime.effective_ability_tags(spec)
	snapshot.cooldown = asc.ability_runtime.get_ability_cooldown_state(spec.handle)
	snapshot.last_activation_result = spec.last_activation_result
	if spec.definition != null:
		snapshot.instancing_policy = spec.definition.instancing_policy
		snapshot.activation_policy = spec.definition.activation_policy
	if spec.per_actor_instance != null:
		snapshot.active_instances.append(spec.per_actor_instance)
	snapshot.active_instances.append_array(spec.active_instances)
	return snapshot
