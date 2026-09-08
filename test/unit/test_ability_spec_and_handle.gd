## GameplayAbilityHandle and GameplayAbilitySpec: identity, cross-ASC isolation
## and the grant pipeline's own invariants.
##
## Every single-subsystem behaviour the grant pipeline touches already has an
## owner elsewhere - costs and cooldowns in test_ability_commit.gd, input
## routing in test_ability_input.gd, GLoot's exact-retirement contract in
## test_gloot_bridge.gd. What none of them assert is the registry's own
## identity rules: what a handle IS, what makes two of them the same or not,
## and what the spec it names actually holds - which is what this task's own
## acceptance list asks for.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const PROBE_TAG: StringName = &"Ability.Probe"
const SLOT: int = 3

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Subject")
	add_child_autofree(fixture.owner)
	asc = fixture.asc


func after_each() -> void:
	fixture = null
	asc = null


func _scene() -> PackedScene:
	var probe: ProbeAbility = Probe.build(PROBE_TAG)
	var scene: PackedScene = PackedScene.new()
	scene.pack(probe)
	probe.free()
	return scene


#region Handle identity
func test_the_default_handle_is_invalid() -> void:
	var handle: GameplayAbilityHandle = GameplayAbilityHandle.new()
	assert_false(handle.is_valid(), "owner 0, id 0")
	assert_eq(handle.id, GameplayAbilityHandle.INVALID_ID)


func test_handle_ids_are_monotonic_within_one_asc() -> void:
	var first: GameplayAbilityHandle = asc.give_ability(_scene())
	var second: GameplayAbilityHandle = asc.give_ability(_scene())
	assert_true(first.is_valid())
	assert_true(second.is_valid())
	assert_true(second.id > first.id, "each grant advances the same counter")


func test_two_ascs_can_both_report_local_id_one_without_colliding() -> void:
	var other: ASCFixture = Fixture.create("Other")
	add_child_autofree(other.owner)

	var mine: GameplayAbilityHandle = asc.give_ability(_scene())
	var theirs: GameplayAbilityHandle = other.asc.give_ability(_scene())

	assert_eq(mine.id, theirs.id, "both ASCs start their own counter at 1")
	assert_false(mine.same_as(theirs), "differing owner_instance_id makes them different handles")


func test_a_handle_from_another_asc_does_not_resolve_here() -> void:
	var other: ASCFixture = Fixture.create("Other")
	add_child_autofree(other.owner)
	var foreign: GameplayAbilityHandle = other.asc.give_ability(_scene())

	assert_null(asc.ability_runtime.get_spec(foreign), "wrong owner, not found by coincidence of id")


func test_a_handle_from_another_asc_cannot_remove_a_spec_here() -> void:
	var other: ASCFixture = Fixture.create("Other")
	add_child_autofree(other.owner)
	var mine: GameplayAbilityHandle = asc.give_ability(_scene())
	var foreign: GameplayAbilityHandle = other.asc.give_ability(_scene())

	assert_false(asc.ability_runtime.remove_ability(foreign), "refused, not silently ignored")
	assert_not_null(asc.ability_runtime.get_spec(mine), "the real grant here is untouched")
	assert_not_null(other.asc.ability_runtime.get_spec(foreign), "and the other ASC's own grant survives too")


func test_an_unknown_handle_resolves_to_nothing() -> void:
	var unknown: GameplayAbilityHandle = GameplayAbilityHandle.new()
	unknown.owner_instance_id = asc.get_instance_id()
	unknown.id = 999999
	assert_null(asc.ability_runtime.get_spec(unknown))


## A handle answers is_valid() forever - ids are never reused - but the spec
## it named is gone once removed, and the handle must not resolve to whatever
## the next grant happens to reuse (it never does, since ids only advance).
func test_a_removed_handle_stays_valid_but_resolves_to_nothing() -> void:
	var handle: GameplayAbilityHandle = asc.give_ability(_scene())
	asc.ability_runtime.remove_ability(handle)

	assert_true(handle.is_valid(), "removal does not retroactively invalidate the handle")
	assert_null(asc.ability_runtime.get_spec(handle), "but it no longer names anything")
#endregion


#region What specs() hands back
func test_specs_returns_a_copy_the_caller_cannot_use_to_mutate_the_registry() -> void:
	asc.give_ability(_scene())
	var collected: Array[GameplayAbilitySpec] = asc.ability_runtime.specs()
	collected.clear()
	assert_eq(asc.ability_runtime.specs().size(), 1, "clearing the copy left the registry alone")
#endregion


#region What lives on the spec
func test_level_and_input_are_read_from_the_spec() -> void:
	var handle: GameplayAbilityHandle = asc.give_ability(_scene(), 3.5, SLOT)
	var spec: GameplayAbilitySpec = asc.ability_runtime.get_spec(handle)

	assert_almost_eq(spec.level, 3.5, 0.0001)
	assert_eq(spec.input_id, SLOT)

	var instance: ProbeAbility = spec.per_actor_instance as ProbeAbility
	assert_almost_eq(instance.get_ability_level(), 3.5, 0.0001, "the instance answers from the spec")
	assert_eq(instance.get_input_id(), SLOT)


func test_the_source_passed_to_give_ability_lands_on_the_spec() -> void:
	var source: GameplayAbilityNamedSource = GameplayAbilityNamedSource.new()
	source.id = &"quest_reward"

	var handle: GameplayAbilityHandle = asc.give_ability(_scene(), 1.0, -1, source)
	var spec: GameplayAbilitySpec = asc.ability_runtime.get_spec(handle)

	assert_eq(spec.source, source)


func test_dynamic_tags_are_independent_between_two_grants() -> void:
	var a: GameplayAbilitySpec = asc.ability_runtime.get_spec(asc.give_ability(_scene()))
	var b: GameplayAbilitySpec = asc.ability_runtime.get_spec(asc.give_ability(_scene()))

	a.dynamic_tags.append(&"State.Marked")

	assert_eq(a.dynamic_tags.size(), 1)
	assert_eq(b.dynamic_tags.size(), 0, "the second grant's array is its own, not a shared reference")


func test_the_instance_is_bound_back_to_its_own_spec() -> void:
	var handle: GameplayAbilityHandle = asc.give_ability(_scene())
	var spec: GameplayAbilitySpec = asc.ability_runtime.get_spec(handle)

	assert_eq(spec.per_actor_instance.current_spec, spec, "the Node points back at the same spec")
	assert_eq(spec.per_actor_instance.owner_asc, asc)
	assert_eq(spec.per_actor_instance.get_ability_handle().id, handle.id)
#endregion


#region Removing the wrong handle
func test_removing_one_handle_leaves_an_unrelated_grant_alone() -> void:
	var kept: GameplayAbilityHandle = asc.give_ability(_scene())
	var dropped: GameplayAbilityHandle = asc.give_ability(_scene())

	assert_true(asc.ability_runtime.remove_ability(dropped))
	assert_not_null(asc.ability_runtime.get_spec(kept), "its neighbour is untouched")
	assert_null(asc.ability_runtime.get_spec(dropped))
#endregion


#region A failed grant consumes no partial state
func test_a_scene_whose_root_is_not_an_ability_registers_nothing() -> void:
	var plain: PackedScene = PackedScene.new()
	var node: Node = Node.new()
	node.name = "NotAnAbility"
	plain.pack(node)
	node.free()

	var handle: GameplayAbilityHandle = asc.give_ability(plain)

	assert_false(handle.is_valid(), "the grant never happened")
	assert_eq(asc.ability_runtime.specs().size(), 0, "nothing was registered")


func test_a_missing_scene_registers_nothing() -> void:
	var handle: GameplayAbilityHandle = asc.give_ability(null)
	assert_false(handle.is_valid())
	assert_eq(asc.ability_runtime.specs().size(), 0)


## discard_prepared_grant is the route a batched grant (GLoot equipping several
## slots at once) uses when a later scene in the batch turns out invalid: the
## earlier, successfully-prepared probes must free without ever having been
## committed.
func test_discarding_a_valid_preparation_frees_it_without_registering_anything() -> void:
	var prepared: PreparedAbilityGrant = asc.ability_runtime.prepare_ability_grant(
		_scene(), 1.0, -1, null
	)
	assert_true(prepared.validation.is_ok())

	asc.ability_runtime.discard_prepared_grant(prepared)

	assert_eq(asc.ability_runtime.specs().size(), 0, "a discarded preparation was never committed")
#endregion


#region Cleanup
func test_cleanup_empties_the_spec_registry() -> void:
	asc.give_ability(_scene())
	asc.give_ability(_scene())
	assert_eq(asc.ability_runtime.specs().size(), 2)

	asc.cleanup()

	assert_eq(asc.ability_runtime.specs().size(), 0, "nothing granted survives cleanup")
#endregion
#region Reachable from the component itself
## Eight ordinary questions about an ability that used to be answerable only
## through `asc.ability_runtime`.
##
## Game code was reaching past the component to ask them - four places inside
## this addon were doing it too - which means the runtime's shape was part of
## the public contract by accident. These are pass-throughs and nothing more:
## what each one is worth proving is that it is there, that it kept the
## runtime's own return type, and that it did the thing.
func test_the_component_answers_for_every_grant_it_holds() -> void:
	var first: GameplayAbilityHandle = asc.give_ability(_scene())
	var second: GameplayAbilityHandle = asc.give_ability(_scene())

	var held: Array[GameplayAbilitySpec] = asc.get_ability_specs()
	assert_eq(held.size(), 2, "both grants, from the component")
	assert_true(asc.get_ability_spec(first) in held, "the first is one of them")
	assert_true(asc.get_ability_spec(second) in held, "and the second")


func test_grant_and_run_once_answers_with_a_result_rather_than_a_handle() -> void:
	var ran: GameplayAbilityActivationResult = asc.give_ability_and_activate_once(_scene())

	assert_true(ran.is_ok(), "it started: %s" % ran.status)
	assert_true(
		asc.get_ability_specs().is_empty(),
		"and the grant is gone again, which is what once means"
	)


## The refusal survives the pass-through. A caller that got a bare bool back
## would have to guess which of half a dozen reasons it was.
func test_a_refused_grant_and_run_once_still_says_why() -> void:
	asc.add_tag(&"Status.Silenced")
	var probe: ProbeAbility = Probe.build(PROBE_TAG)
	probe.activation_blocked_query = GameplayTagQuery.new()
	probe.activation_blocked_query.root = GameplayTagQueryExpression.new()
	probe.activation_blocked_query.root.operator = GameplayTagQueryExpression.Operator.ANY
	probe.activation_blocked_query.root.tags = [&"Status.Silenced"] as Array[StringName]
	var scene: PackedScene = PackedScene.new()
	scene.pack(probe)
	probe.free()

	var ran: GameplayAbilityActivationResult = asc.give_ability_and_activate_once(scene)

	assert_false(ran.is_ok(), "blocked")
	# By the result's own vocabulary. It is a different enum from
	# AbilityRuntime.ActivationError on purpose: one is why the runtime
	# refused, the other is what a caller is handed, and they do not line up
	# value for value.
	assert_eq(
		ran.status,
		GameplayAbilityActivationResult.Status.BLOCKED_BY_TAGS,
		"and it says which"
	)


func test_retire_on_end_is_asked_of_the_component() -> void:
	var handle: GameplayAbilityHandle = asc.give_ability(_scene())

	assert_true(asc.set_remove_ability_on_end(handle), "the grant is known here")
	assert_false(
		asc.set_remove_ability_on_end(GameplayAbilityHandle.new()),
		"and one that is not, is not"
	)


func test_a_grants_cooldown_state_is_asked_of_the_component() -> void:
	var handle: GameplayAbilityHandle = asc.give_ability(_scene())
	var state: AbilityCooldownState = asc.get_ability_cooldown_state(handle)

	assert_not_null(state, "there is always an answer")
	assert_false(state.active, "and nothing has been committed yet")


## Held inputs stay ints. They are slots the component routes by, and a caller
## that got names back would be holding a second vocabulary for the same thing.
func test_the_component_reports_the_input_slots_it_is_holding() -> void:
	var handle: GameplayAbilityHandle = asc.give_ability(_scene(), 1.0, SLOT)
	assert_true(handle.is_valid(), "granted onto a slot")

	assert_eq(asc.get_held_inputs(), [] as Array[int], "nothing is held to start")

	asc.ability_local_input_pressed(SLOT)
	assert_eq(asc.get_held_inputs(), [SLOT] as Array[int], "the slot, as an int")

	asc.ability_local_input_released(SLOT)
	assert_eq(asc.get_held_inputs(), [] as Array[int], "and let go again")


func test_cancelling_by_query_and_cancelling_everything_both_run_here() -> void:
	asc.give_ability_and_activate_once(_scene())

	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = GameplayTagQueryExpression.new()
	query.root.operator = GameplayTagQueryExpression.Operator.ANY
	query.root.tags = [PROBE_TAG] as Array[StringName]

	# Neither has anything to cancel here, and the point is that both are
	# reachable and neither refuses: the runtime already owns what they mean.
	asc.cancel_abilities_matching(query)
	asc.cancel_all_abilities()
	assert_true(asc.get_ability_specs().is_empty(), "nothing was left running")


func test_clearing_every_grant_is_asked_of_the_component() -> void:
	asc.give_ability(_scene())
	asc.give_ability(_scene())
	assert_eq(asc.get_ability_specs().size(), 2, "two grants")

	asc.clear_all_abilities()

	assert_true(asc.get_ability_specs().is_empty(), "and none")
#endregion
