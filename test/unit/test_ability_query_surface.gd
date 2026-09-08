## Asking a component about its abilities, instead of iterating its runtime.
##
## Every question here was reachable before only by walking `ability_runtime`
## from game code, which made the runtime's shape part of the public contract by
## accident - and four places inside this addon were doing it too.
##
## The one with teeth is the external block. It is counted rather than flagged,
## because a cutscene and a stun that both block, and one that ends, used to
## unblock for both - and that bug reads as "the stun ended early" somewhere
## else entirely.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const FIRE: StringName = &"Ability.Fire"
const ICE: StringName = &"Ability.Ice"
const SLOT: int = 4
const OTHER_SLOT: int = 5

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Caster")
	add_child_autofree(fixture.owner)
	asc = fixture.asc


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
func _query(tags: Array[StringName]) -> GameplayTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = tags
	var made: GameplayTagQuery = GameplayTagQuery.new()
	made.root = expression
	return made


func _grant(tag: StringName, input_id: int = -1) -> GameplayAbilitySpec:
	var probe: ProbeAbility = Probe.build(tag)
	return AbilityFactory.give(asc, probe, 1.0, input_id)
#endregion


#region Finding
func test_specs_are_found_by_query_in_the_order_they_were_granted() -> void:
	var first: GameplayAbilitySpec = _grant(FIRE)
	var second: GameplayAbilitySpec = _grant(ICE)
	var third: GameplayAbilitySpec = _grant(FIRE)

	var found: Array[GameplayAbilitySpec] = asc.find_ability_specs(
		_query([FIRE] as Array[StringName])
	)

	assert_eq(found, [first, third] as Array[GameplayAbilitySpec], "both fires, in grant order")
	assert_false(found.has(second), "and not the one that does not match")


## The query reads what the grant effectively has, which is its authored tags
## plus whatever was added to this grant in particular.
func test_query_activation_uses_effective_ability_tags() -> void:
	var spec: GameplayAbilitySpec = _grant(FIRE)
	spec.dynamic_tags = [&"Ability.Empowered"] as Array[StringName]

	var started: Array[GameplayAbilityHandle] = asc.try_activate_abilities_by_query(
		_query([&"Ability.Empowered"] as Array[StringName])
	)

	assert_eq(started, [spec.handle] as Array[GameplayAbilityHandle], "the dynamic tag counted")


func test_a_spec_is_found_by_the_input_slot_it_is_bound_to() -> void:
	var bound: GameplayAbilitySpec = _grant(FIRE, SLOT)
	_grant(ICE, OTHER_SLOT)

	assert_eq(asc.find_ability_spec_by_input(SLOT), bound, "the one on that slot")
	assert_null(asc.find_ability_spec_by_input(99), "and nothing on a slot nobody took")


func test_a_spec_is_found_by_its_ability_script() -> void:
	var spec: GameplayAbilitySpec = _grant(FIRE)
	# Through the preloaded script rather than off an instance: get_script()
	# answers Variant, and casting one is unsafe under this project's warnings.
	var script: Script = Probe

	assert_eq(asc.find_ability_spec_by_script(script), spec, "found by what it is")
	assert_null(asc.find_ability_spec_by_script(null), "and nothing for nothing")


func test_grants_on_one_input_slot_are_cleared_together() -> void:
	_grant(FIRE, SLOT)
	_grant(ICE, SLOT)
	var kept: GameplayAbilitySpec = _grant(FIRE, OTHER_SLOT)

	assert_eq(asc.clear_abilities_with_input(SLOT), 2, "both on that slot")
	assert_eq(asc.get_ability_specs(), [kept] as Array[GameplayAbilitySpec], "the other stayed")


func test_the_effect_that_granted_an_ability_can_be_asked_for() -> void:
	var spec: GameplayAbilitySpec = _grant(FIRE)

	assert_null(
		asc.find_effect_handle_that_granted(spec.handle),
		"nothing granted this one but the caller"
	)
#endregion


#region Blocks asked for from outside
func test_an_external_block_refuses_with_its_own_reason() -> void:
	var spec: GameplayAbilitySpec = _grant(FIRE)
	asc.block_abilities_with_query(_query([FIRE] as Array[StringName]))

	assert_true(asc.is_ability_blocked(spec), "the component says so")

	var refused: GameplayAbilityActivationResult = asc.try_activate_ability_handle(spec.handle)
	assert_false(refused.is_ok(), "and it does not start")
	assert_eq(
		refused.status,
		GameplayAbilityActivationResult.Status.BLOCKED_EXTERNALLY,
		"with a reason no granted ability explains"
	)


## Two systems blocking, one unblocking, leaves the other's block standing.
func test_external_ability_blocks_are_reference_counted() -> void:
	var spec: GameplayAbilitySpec = _grant(FIRE)
	var cutscene: GameplayTagQuery = _query([FIRE] as Array[StringName])
	var stun: GameplayTagQuery = _query([FIRE] as Array[StringName])

	asc.block_abilities_with_query(cutscene)
	asc.block_abilities_with_query(stun)
	asc.unblock_abilities_with_query(cutscene)

	assert_true(asc.is_ability_blocked(spec), "the other one is still holding it")

	asc.unblock_abilities_with_query(stun)
	assert_false(asc.is_ability_blocked(spec), "and now nobody is")


func test_unblocking_something_nobody_blocked_does_nothing() -> void:
	var spec: GameplayAbilitySpec = _grant(FIRE)

	asc.unblock_abilities_with_query(_query([FIRE] as Array[StringName]))

	assert_false(asc.is_ability_blocked(spec), "it was never blocked")
	assert_true(asc.try_activate_ability_handle(spec.handle).is_ok(), "and still starts")


func test_a_block_only_covers_what_its_query_matches() -> void:
	var fire: GameplayAbilitySpec = _grant(FIRE)
	var ice: GameplayAbilitySpec = _grant(ICE)

	asc.block_abilities_with_query(_query([FIRE] as Array[StringName]))

	assert_true(asc.is_ability_blocked(fire), "the one it named")
	assert_false(asc.is_ability_blocked(ice), "and not the one it did not")
#endregion


#region Holding a tag a number of times
func test_a_tag_count_is_set_by_adding_and_removing() -> void:
	asc.add_tag(&"Status.Marked")

	asc.set_tag_count(&"Status.Marked", 3)
	assert_eq(asc.tags.count_exact(&"Status.Marked"), 3, "up to three")

	asc.set_tag_count(&"Status.Marked", 1)
	assert_eq(asc.tags.count_exact(&"Status.Marked"), 1, "and back down to one")

	asc.set_tag_count(&"Status.Marked", 0)
	assert_false(asc.has_tag_exact(&"Status.Marked"), "and gone")


## Through the doors that announce, so everything watching hears what it watches.
##
## The two signals are different questions and the counts differ accordingly:
## arriving happened once, and the number of holds moved twice. A setter that
## wrote the field would have announced neither.
func test_setting_a_tag_count_announces_every_step() -> void:
	watch_signals(asc)

	asc.set_tag_count(&"Status.Marked", 2)

	assert_signal_emit_count(asc, "tag_added", 1, "it arrived once")
	assert_signal_emit_count(asc, "tag_count_changed", 2, "and the count moved twice")
#endregion


#region Where the component is
## A node that says where its ability system is has said so, and a convention
## that overruled it would be the engine deciding it knows better.
func test_locator_prefers_the_explicit_ability_system_interface() -> void:
	var other: ASCFixture = Fixture.create("Elsewhere")
	add_child_autofree(other.owner)

	var speaker: ExplicitAbilitySystemNode = ExplicitAbilitySystemNode.new()
	speaker.declared = other.asc
	fixture.owner.add_child(speaker)

	assert_eq(
		AbilitySystemLocator.find_for_node(speaker),
		other.asc,
		"what it said, not what it is under"
	)


func test_locator_still_walks_the_tree_when_nobody_says_anything() -> void:
	var plain: Node = Node.new()
	fixture.owner.add_child(plain)

	assert_eq(AbilitySystemLocator.find_for_node(plain), asc, "the convention still answers")
#endregion
