## Finding granted abilities, and the blocks somebody outside asked for.
##
## Split out of AbilityRuntime the way AbilityInstancingRuntime and
## AbilityTagSemanticsRuntime were: the registry holds the grants, and this
## answers questions about them. Two different jobs that grew into one file.
##
## The blocks are the part with teeth. They are counted rather than flagged,
## because a cutscene and a stun that both block, and one that ends, would
## otherwise unblock for both - and that bug reads as "the stun ended early"
## somewhere else entirely.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityQueryRuntime extends RefCounted

var ability_runtime: AbilityRuntime = null


## Queries somebody outside the ability system asked to have blocked, and how
## many times each was asked for.
##
## Counted rather than flagged. Two systems that both block - a cutscene and
## a stun - and one that unblocks would otherwise unblock for both, and the
## bug reads as "the stun ended early" somewhere else entirely.
##
## Keyed by what the query says rather than by the object, so a caller that
## builds an equivalent query to unblock with is understood. An identity key
## would mean a caller had to keep the exact Resource it blocked with.
var _external_blocks: Dictionary[String, int] = {}
var _external_queries: Dictionary[String, GameplayTagQuery] = {}


## Block every ability whose effective tags match. One more call, one more
## unblock needed.
func block_with_query(query: GameplayTagQuery) -> void:
	if query == null or query.is_empty():
		return
	var key: String = _key_of(query)
	_external_blocks[key] = _external_blocks.get(key, 0) + 1
	_external_queries[key] = query


## Take one block back. Unblocking something nobody blocked does nothing and
## says nothing: it is a caller tidying up after a branch it did not take.
func unblock_with_query(query: GameplayTagQuery) -> void:
	if query == null or query.is_empty():
		return
	var key: String = _key_of(query)
	var held: int = _external_blocks.get(key, 0)
	if held <= 1:
		_external_blocks.erase(key)
		_external_queries.erase(key)
		return
	_external_blocks[key] = held - 1


## Whether any outstanding external block covers this spec.
func blocked_externally(spec: GameplayAbilitySpec) -> bool:
	if spec == null or _external_blocks.is_empty():
		return false
	var carried: Array[StringName] = AbilityRuntime.effective_ability_tags(spec)
	for key: String in _external_queries:
		if _external_queries[key].matches_tags(carried):
			return true
	return false


## What a query says, as a string two equivalent queries agree on.
static func _key_of(query: GameplayTagQuery) -> String:
	return _key_of_expression(query.root)


static func _key_of_expression(expression: GameplayTagQueryExpression) -> String:
	if expression == null:
		return ""
	var tags: Array[StringName] = expression.tags.duplicate()
	tags.sort()
	var children: Array[String] = []
	for child: GameplayTagQueryExpression in expression.expressions:
		children.append(_key_of_expression(child))
	children.sort()
	return "%d(%s)[%s]" % [expression.operator, ",".join(tags), ",".join(children)]


## Every grant whose effective tags match, in the order they were granted.
##
## Grant order rather than any other, because it is the only order a caller
## can predict, and a list whose order moved between calls would make a UI
## built on it jump.
func specs_matching(query: GameplayTagQuery) -> Array[GameplayAbilitySpec]:
	var found: Array[GameplayAbilitySpec] = []
	if query == null or query.is_empty():
		return found
	for spec: GameplayAbilitySpec in ability_runtime.specs():
		if query.matches_tags(AbilityRuntime.effective_ability_tags(spec)):
			found.append(spec)
	return found


## The first grant bound to this input slot, or nothing.
func spec_for_input(input_id: int) -> GameplayAbilitySpec:
	for spec: GameplayAbilitySpec in ability_runtime.specs():
		if spec.input_id == input_id:
			return spec
	return null


## The first grant of this ability script, which is what "by class" means
## where a class is a script.
func spec_for_script(script: Script) -> GameplayAbilitySpec:
	if script == null:
		return null
	for spec: GameplayAbilitySpec in ability_runtime.specs():
		if spec.definition == null or spec.definition.ability_scene == null:
			continue
		var state: SceneState = spec.definition.ability_scene.get_state()
		if state.get_node_count() == 0:
			continue
		for index: int in state.get_node_property_count(0):
			if state.get_node_property_name(0, index) != &"script":
				continue
			if state.get_node_property_value(0, index) == script:
				return spec
	return null


## Retire every grant bound to this slot. Answers how many went.
func clear_specs_with_input(input_id: int) -> int:
	var going: Array[GameplayAbilitySpec] = []
	for spec: GameplayAbilitySpec in ability_runtime.specs():
		if spec.input_id == input_id:
			going.append(spec)
	for spec: GameplayAbilitySpec in going:
		ability_runtime.remove_ability(spec.handle)
	return going.size()


## Which effect granted this ability, when one did.
func effect_that_granted(handle: GameplayAbilityHandle) -> GameplayEffectHandle:
	var spec: GameplayAbilitySpec = ability_runtime.get_spec(handle)
	if spec == null:
		return null
	var from_effect: GameplayAbilityEffectSource = spec.source as GameplayAbilityEffectSource
	return from_effect.effect_handle if from_effect != null else null


## Every provider still choosing, across every running ability.
##
## A snapshot: confirming one can end an ability, which calls off the rest,
## and a loop reading the live lists while that happens is reading lists that
## moved under it.
func previewing_providers(deaf: Array[GameplayAbility] = []) -> Array[GameplayTargetProvider]:
	var waiting: Array[GameplayTargetProvider] = []
	for spec: GameplayAbilitySpec in ability_runtime.specs():
		for instance: GameplayAbility in _instances_of(spec):
			if deaf.has(instance):
				continue
			for provider: GameplayTargetProvider in instance.aiming_providers():
				if provider.is_choosing():
					waiting.append(provider)
	return waiting


## Every live instance whose grant does not hear a remote machine saying no.
##
## The list a cancel that arrived over a wire has to skip. Whether an
## activation can be called off from elsewhere is a property of the grant
## rather than of the run, so it is read off the frozen definition and the
## instances behind that grant are what comes back.
func deaf_to_remote_cancellation() -> Array[GameplayAbility]:
	var deaf: Array[GameplayAbility] = []
	for spec: GameplayAbilitySpec in ability_runtime.specs():
		if spec.definition == null or spec.definition.accepts_remote_termination():
			continue
		deaf.append_array(_instances_of(spec))
	return deaf


## The first grant made from this ability scene.
##
## What a networking layer holding a definition has to ask, because a wire
## names a definition and never a handle: the slot a press is about is the
## one this machine's own grant was bound to.
func spec_for_scene(scene: PackedScene) -> GameplayAbilitySpec:
	if scene == null:
		return null
	for spec: GameplayAbilitySpec in ability_runtime.specs():
		if spec.definition != null and spec.definition.ability_scene == scene:
			return spec
	return null


## Every live instance behind one grant, whichever instancing policy it has.
func _instances_of(spec: GameplayAbilitySpec) -> Array[GameplayAbility]:
	var running: Array[GameplayAbility] = []
	if spec.per_actor_instance != null and is_instance_valid(spec.per_actor_instance):
		running.append(spec.per_actor_instance)
	for execution: GameplayAbility in spec.active_instances:
		if is_instance_valid(execution):
			running.append(execution)
	return running
