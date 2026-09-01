## Task 15's complete tag semantics: effective tags, cancel/block matching
## between abilities and against block-carrying active effects, and
## activation-owned tag refcounting.
##
## Split out of AbilityRuntime the same way AbilityInstancingRuntime/
## AbilityTaskRuntime are: a focused collaborator, composed into the parent
## rather than folded inside it.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name AbilityTagSemanticsRuntime extends RefCounted

var owner_asc: AbilitySystemComponent = null
var ability_runtime: AbilityRuntime = null


#region Effective tags
## The one place ability_tags + spec.dynamic_tags are combined - the gate,
## cancel matching, and block matching all ask this instead of each keeping
## its own copy.
static func effective_ability_tags(spec: GameplayAbilitySpec) -> Array[StringName]:
	var result: Array[StringName] = []
	if spec == null:
		return result
	if spec.definition != null:
		result.append_array(spec.definition.ability_tags)
	result.append_array(spec.dynamic_tags)
	return result
#endregion


#region Block
## True while `spec` is blocked by another granted spec's own
## block_abilities_query (active_count > 0), or by an uninhibited active
## effect's GameplayEffectBlockAbilityTagsComponent query.
func blocked_by_active_ability(spec: GameplayAbilitySpec) -> bool:
	var candidate_tags: Array[StringName] = effective_ability_tags(spec)
	for other: GameplayAbilitySpec in ability_runtime.specs():
		if other == spec or other.active_count <= 0 or other.definition == null:
			continue
		var query: GameplayTagQuery = other.definition.block_abilities_query
		if query != null and not query.is_empty() and query.matches_tags(candidate_tags):
			return true
	if owner_asc == null:
		return false
	for active: ActiveGameplayEffect in owner_asc.effects.active_effects():
		if active.inhibited:
			continue
		var block_query: GameplayTagQuery = active.get_effect_def().get_block_ability_tags_query()
		if block_query != null and not block_query.is_empty() and block_query.matches_tags(candidate_tags):
			return true
	return false
#endregion


#region Cancel
## Aborts every running instance of every granted spec (other than
## `excluding`) whose effective tags match `query` - the one cancellation
## algorithm. GameplayEffectCancelAbilityTagsComponent, a successful
## activation's own cancel_abilities_query, and legacy cancel_with_tags all
## delegate here.
func cancel_matching_query(query: GameplayTagQuery, excluding: GameplayAbilitySpec = null) -> void:
	if query == null or query.is_empty():
		return
	for spec: GameplayAbilitySpec in ability_runtime.specs():
		if spec == excluding or spec.definition == null:
			continue
		if query.matches_tags(effective_ability_tags(spec)):
			_abort_every_instance(spec)


## Legacy convenience: any granted spec whose effective tags include one of
## `cancel_tags` is aborted. Built over cancel_matching_query() - no second
## cancellation algorithm.
func cancel_with_tags(cancel_tags: Array[StringName]) -> void:
	if cancel_tags.is_empty():
		return
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = cancel_tags
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = expression
	cancel_matching_query(query)


func _abort_every_instance(spec: GameplayAbilitySpec) -> void:
	var instance: GameplayAbility = spec.per_actor_instance
	if instance != null and is_instance_valid(instance) and instance.is_active:
		instance.abort_ability(GameplayAbilityTask.CancelReason.CANCEL_TAG)
	for execution: GameplayAbility in spec.active_instances.duplicate():
		if is_instance_valid(execution) and execution.is_active:
			execution.abort_ability(GameplayAbilityTask.CancelReason.CANCEL_TAG)


## Every other granted spec whose effective tags match `spec.definition`'s own
## cancel_abilities_query is cancelled - never `spec` itself unless
## allow_self_cancel.
func cancel_conflicting_abilities(spec: GameplayAbilitySpec) -> void:
	if spec == null or spec.definition == null:
		return
	var query: GameplayTagQuery = spec.definition.cancel_abilities_query
	if query == null or query.is_empty():
		return
	var excluding: GameplayAbilitySpec = null if spec.definition.allow_self_cancel else spec
	cancel_matching_query(query, excluding)
#endregion


#region Activation-owned tags
## Granted/retired once per definition, never once per PER_EXECUTION
## instance - `grant` is the caller's own active_count 0<->1 transition.
func set_activation_owned_tags(spec: GameplayAbilitySpec, grant: bool) -> void:
	if owner_asc == null or spec == null or spec.definition == null:
		return
	for tag: StringName in spec.definition.activation_owned_tags:
		if grant:
			owner_asc.add_tag(tag)
		else:
			owner_asc.remove_tag(tag)
#endregion
