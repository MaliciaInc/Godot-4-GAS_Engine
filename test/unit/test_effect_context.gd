## The effect context: who cast this, with what, and at what level.
##
## Split from test_spec_isolation.gd so the plan's file list is real rather
## than approximated. The tests moved; none were duplicated, because two
## copies of an assertion drift the first time either is tuned.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"

var source: ASCFixture = null
var target_a: ASCFixture = null


func before_each() -> void:
	source = Fixture.create("Caster")
	target_a = Fixture.create("TargetA")
	add_child_autofree(source.owner)
	add_child_autofree(target_a.owner)


func after_each() -> void:
	source = null
	target_a = null


#region Context
func test_the_instigator_arrives_intact() -> void:
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	assert_eq(context.instigator, source.owner)


func test_the_causer_defaults_to_the_instigator() -> void:
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	assert_eq(context.causer, source.owner, "no separate causer means the instigator caused it")


func test_a_distinct_causer_is_preserved() -> void:
	var projectile: Node = Node.new()
	add_child_autofree(projectile)
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner, projectile)
	assert_eq(context.instigator, source.owner, "who cast it")
	assert_eq(context.causer, projectile, "what hit them")


func test_the_level_travels_with_the_spec() -> void:
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(
		Factory.infinite([Factory.add(ATTACK, 1.0)]), GameplayEffectContext.new(source.owner), 7.0
	)
	assert_almost_eq(spec.level, 7.0, TOLERANCE)


func test_source_and_target_are_different_nodes() -> void:
	# A suite where both sides are the same node can pass while the engine
	# conflates them, so this is asserted rather than assumed.
	assert_ne(source.owner, target_a.owner)
	assert_ne(source.asc, target_a.asc)
#endregion


#region Ability handle, source object and payloads
## A payload whose create_application_copy() deliberately fails - the only
## way to exercise "a payload that cannot be copied" without depending on
## the base class's own push_error stub.
class UncopyablePayload extends GameplayEffectContextPayload:
	func create_application_copy() -> GameplayEffectContextPayload:
		return null


func test_target_data_starts_fresh_and_empty_on_a_copy() -> void:
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	context.target_data.append_node(target_a.owner)
	assert_true(context.has_targets(), "the original has a target")

	var copy: GameplayEffectContext = context.create_application_copy()
	assert_false(copy.has_targets(), "the copy starts with none of the original's targets")
	assert_ne(copy.target_data, context.target_data, "and it is not the same object either")


func test_ability_handle_defaults_null_and_survives_a_copy() -> void:
	var bare: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	assert_null(bare.ability_handle)

	var handle: GameplayAbilityHandle = GameplayAbilityHandle.new()
	handle.owner_instance_id = 1
	handle.id = 1
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	context.ability_handle = handle

	var copy: GameplayEffectContext = context.create_application_copy()
	assert_eq(copy.ability_handle, handle, "the same logical handle, not a new one")


func test_source_object_survives_a_copy() -> void:
	var weapon: Node = Node.new()
	add_child_autofree(weapon)
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	context.source_object = weapon

	var copy: GameplayEffectContext = context.create_application_copy()
	assert_eq(copy.source_object, weapon)


func test_one_payload_is_added_and_found_by_script() -> void:
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	var payload: GameplayHitContextPayload = GameplayHitContextPayload.new()
	payload.hit = GameplayTargetHit.new()

	assert_true(context.add_payload(payload))
	assert_true(context.has_payload_script(GameplayHitContextPayload))
	assert_eq(context.find_payload(GameplayHitContextPayload), payload)
	assert_false(context.has_payload_script(GameplayEffectContextPayload), "the abstract base is a different script")


func test_add_payload_refuses_null() -> void:
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	assert_false(context.add_payload(null))
	assert_true(context.payloads.is_empty())


func test_multiple_payloads_all_survive_a_copy_in_order() -> void:
	var hit_payload: GameplayHitContextPayload = GameplayHitContextPayload.new()
	hit_payload.hit = GameplayTargetHit.new()
	var second: GameplayHitContextPayload = GameplayHitContextPayload.new()
	second.hit = GameplayTargetHit.new()

	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	context.add_payload(hit_payload)
	context.add_payload(second)

	var copy: GameplayEffectContext = context.create_application_copy()
	assert_eq(copy.payloads.size(), 2)
	assert_ne(copy.payloads[0], hit_payload, "deep-copied, not the same instance")
	assert_ne(copy.payloads[1], second)
	var copied_hit_payload: GameplayHitContextPayload = copy.payloads[0] as GameplayHitContextPayload
	assert_eq(copied_hit_payload.hit, hit_payload.hit, "the wrapped DTO travels by reference, same as a handle")


func test_copy_isolation_appending_to_one_payload_array_never_touches_the_other() -> void:
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	var payload: GameplayHitContextPayload = GameplayHitContextPayload.new()
	context.add_payload(payload)

	var copy: GameplayEffectContext = context.create_application_copy()
	copy.add_payload(GameplayHitContextPayload.new())

	assert_eq(context.payloads.size(), 1, "the original array is untouched")
	assert_eq(copy.payloads.size(), 2)


func test_a_payload_that_cannot_be_copied_fails_the_whole_application_copy() -> void:
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	context.add_payload(UncopyablePayload.new())

	assert_null(context.create_application_copy(), "explicit failure, never a context missing the payload silently")


func test_no_dictionary_domain_payload() -> void:
	# The lookup boundary is a real Script, never a string key: an unrelated
	# script (one that was never added as a payload) never matches, proving
	# there is no untyped fallback path a Dictionary key could have used.
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	context.add_payload(GameplayHitContextPayload.new())
	var unrelated_script: Script = load("res://addons/GodotGAS/target_data/gameplay_effect_context.gd") as Script
	assert_false(context.has_payload_script(unrelated_script))
#endregion


#region Boundary propagation
## A calculation that only records what it saw, to prove the execution
## boundary reaches the same context object apply_effect_to_targets built -
## never a stripped-down copy.
class ContextProbeExecution extends GameplayExecutionCalculation:
	var seen_source_object: Node = null
	var seen_ability_handle: GameplayAbilityHandle = null

	func execute(
		spec: GameplayEffectSpec, _target_asc: AbilitySystemComponent
	) -> Dictionary[StringName, float]:
		if spec.context != null:
			seen_source_object = spec.context.source_object
			seen_ability_handle = spec.context.ability_handle
		return {}


func test_execution_calculations_see_the_full_context() -> void:
	var weapon: Node = Node.new()
	add_child_autofree(weapon)
	var handle: GameplayAbilityHandle = GameplayAbilityHandle.new()
	handle.owner_instance_id = 1
	handle.id = 1

	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	context.source_object = weapon
	context.ability_handle = handle

	var probe: ContextProbeExecution = ContextProbeExecution.new()
	var effect: GameplayEffect = Factory.instant([])
	effect.executions = [probe]

	target_a.asc.apply_effect_spec_result(GameplayEffectSpec.new(effect, context))

	assert_eq(probe.seen_source_object, weapon)
	assert_eq(probe.seen_ability_handle, handle)


func test_cue_params_carry_the_same_context() -> void:
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	context.source_object = target_a.owner

	var spec: GameplayEffectSpec = GameplayEffectSpec.new(Factory.instant([]), context)
	var params: GameplayCueParams = target_a.asc.effects.cue_params_for(&"Cue.Probe", spec)

	assert_eq(params.context, context, "the same object, not a stripped-down copy")
	assert_eq(params.context.source_object, target_a.owner)


## An overflow child used to build a bare GameplayEffectContext.new(instigator)
## by hand, silently dropping causer and ability_handle - now it goes through
## GameplayEffectContext.derive_child_context(), the same fallback an
## Additional Effects child uses.
func test_overflow_child_inherits_causer_and_ability_handle() -> void:
	var projectile: Node = Node.new()
	add_child_autofree(projectile)
	var handle: GameplayAbilityHandle = GameplayAbilityHandle.new()
	handle.owner_instance_id = 1
	handle.id = 1
	var burst: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 3.0)])
	var stacked: GameplayEffect = Factory.with_overflow_effects(
		Factory.stacked(Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 1), [burst]
	)

	for _i: int in 2:
		var context: GameplayEffectContext = GameplayEffectContext.new(source.owner, projectile)
		context.ability_handle = handle
		target_a.asc.apply_effect_spec_result(GameplayEffectSpec.new(stacked, context))

	var burst_active: ActiveGameplayEffect = null
	for active: ActiveGameplayEffect in target_a.asc.get_active_effects():
		if active.get_effect_def() == burst:
			burst_active = active
	assert_not_null(burst_active, "the burst overflow effect fired")
	assert_eq(burst_active.spec.context.causer, projectile, "causer used to be lost here")
	assert_eq(burst_active.spec.context.ability_handle, handle)
#endregion
