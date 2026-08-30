## How a spec's instancing policy turns into a running Node.
##
## PER_ACTOR reuses the one instance its grant created; PER_EXECUTION makes a
## fresh one per activation and tracks it until it ends, so two casts of the
## same ability in flight together never share a Node, a task, or a
## `current_context`. Split out of AbilityRuntime rather than folded into it,
## the way AbilityTaskRuntime already is: one focused sub-runtime instead of
## one file answering both "what was granted" and "how it gets instantiated".
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name AbilityInstancingRuntime extends RefCounted

var owner_asc: AbilitySystemComponent = null

## Back-reference for the one question only the owning runtime can answer:
## whether a spec is currently allowed to activate at all.
var ability_runtime: AbilityRuntime = null


## Build one running instance from a spec's frozen definition. The one place
## a PackedScene is instantiated for anything other than the validating probe
## a grant already consumed.
func instantiate_ability(spec: GameplayAbilitySpec) -> GameplayAbility:
	if spec == null or spec.definition == null or spec.definition.ability_scene == null:
		return null
	var node: Node = spec.definition.ability_scene.instantiate()
	var instance: GameplayAbility = node as GameplayAbility
	if instance == null:
		if node != null:
			node.free()
		return null
	instance.current_spec = spec
	instance.owner_asc = owner_asc
	if owner_asc != null:
		owner_asc.add_child(instance)
	return instance


## The instance a fresh activation actually runs on, per the spec's policy.
##
## Only `active_instances` - which instances exist - is kept here.
## `active_count` - how many are actually running - is `try_activate()` and
## `end_ability()`'s alone: they already run for every instance regardless of
## policy, and counting the same activation in two places double-counted it.
func instance_for_activation(spec: GameplayAbilitySpec) -> GameplayAbility:
	if spec == null or spec.definition == null:
		return null
	if spec.definition.instancing_policy == GameplayAbility.InstancingPolicy.PER_ACTOR:
		return spec.per_actor_instance

	var instance: GameplayAbility = instantiate_ability(spec)
	if instance == null:
		return null
	spec.active_instances.append(instance)
	instance.ability_ended.connect(
		func(_was_cancelled: bool) -> void: release_execution_instance(spec, instance)
	)
	return instance


## Retire one PER_EXECUTION instance once it has actually finished - connected
## to `ability_ended`, so this always runs after `end_ability()` has already
## cancelled its tasks, forgotten its commit, and decremented `active_count`.
func release_execution_instance(spec: GameplayAbilitySpec, ability: GameplayAbility) -> void:
	spec.active_instances.erase(ability)
	if is_instance_valid(ability):
		ability.owner_asc = null
		ability.current_spec = null
		ability.queue_free()


## Start a spec running through whatever its instancing policy means by that.
## The one route both input routing and event routing activate a spec
## through, so "how a spec starts" is decided once rather than reimplemented
## per caller.
func activate_spec(spec: GameplayAbilitySpec, context: GameplayEffectContext = null) -> void:
	if ability_runtime == null or ability_runtime.activation_error(spec) != AbilityRuntime.ActivationError.NONE:
		return
	var instance: GameplayAbility = instance_for_activation(spec)
	if instance == null:
		return
	var started: bool = await instance.try_activate(context)
	if not started and spec.definition.instancing_policy == GameplayAbility.InstancingPolicy.PER_EXECUTION:
		# try_activate can only refuse here if gate state changed between the
		# pre-check above and its own internal re-check - an instance was
		# already spent creating it, and nothing else will ever end it to
		# reach the normal release path above.
		release_execution_instance(spec, instance)
