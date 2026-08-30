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
## @meta_license: MIT
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
