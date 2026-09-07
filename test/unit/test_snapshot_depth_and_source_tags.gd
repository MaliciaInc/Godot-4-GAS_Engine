## What a grant captured, what it must refuse to publish, and when a source's
## tags were read.
##
## Three things that were shallow when they had to be deep, or late when they
## had to be once.
##
## A grant snapshots the ability's definition so that every later decision -
## pricing, gating, timing - reads one frozen thing. It copied the arrays and
## kept the Resources inside them, so an author still holding the cost Resource
## could reach into the snapshot through it and change what an ability charges
## after it was granted. The copy is deep now, and what it deliberately keeps is
## aliasing: one Resource listed twice stays one object, because "a cooldown
## listed twice is applied once" is decided by comparing them.
##
## An application published its contributions and then found out whether the
## aggregate they produced could be composed at all. A magnitude that overflows
## to infinity was already in the runtime by the time anybody noticed, and the
## attribute stopped recomposing for every other effect too. The aggregate is
## now composed against a copy first, and nothing is published unless it works.
##
## And a source's tags were snapshotted only when the source ASC was resolved
## for the first time, which asks a question nobody meant: an application with
## no source has no tags and was re-read forever, while one whose source arrived
## late never captured at all.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const MANA: StringName = &"mana"
const ATTACK: StringName = &"attack"
const PROBE_TAG: StringName = &"Ability.Probe"
const COOLDOWN_TAG: StringName = &"Cooldown.Probe"
const BLESSED: StringName = &"State.Blessed"
const CURSED: StringName = &"State.Cursed"

var source: ASCFixture = null
var target: ASCFixture = null


func before_each() -> void:
	source = Fixture.create("Source")
	target = Fixture.create("Target")
	add_child_autofree(source.owner)
	add_child_autofree(target.owner)
	source.asc.set_process(false)
	target.asc.set_process(false)


func after_each() -> void:
	source = null
	target = null


#region Getting there
func _cost(amount: float) -> GameplayAbilityCost:
	var made: GameplayAbilityCost = GameplayAbilityCost.new()
	made.mode = GameplayAbilityCost.Mode.ABSOLUTE
	made.target_attribute = MANA
	made.amount = GameplayScalableFloat.new()
	made.amount.value = amount
	return made


func _tag_query(tag: StringName) -> GameplayTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = [tag] as Array[StringName]
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = expression
	return query


func _cooldown() -> GameplayEffect:
	var no_modifiers: Array[GameplayEffectModifier] = []
	return Factory.granting(Factory.duration(no_modifiers, 5.0), [COOLDOWN_TAG])


func _granted(configure: Callable) -> GameplayAbilitySpec:
	var probe: ProbeAbility = Probe.build(PROBE_TAG)
	configure.call(probe)
	return AbilityFactory.give(target.asc, probe)
#endregion


#region What a grant owns afterwards
## An author who keeps the cost Resource cannot reprice a granted ability.
##
## B14. The snapshot duplicated the array and kept the Resources in it, so this
## was not a copy at all: the object the snapshot priced from and the object the
## author still held were the same one.
func test_editing_a_cost_resource_after_the_grant_does_not_reprice_the_ability() -> void:
	var authored: GameplayAbilityCost = _cost(10.0)
	var spec: GameplayAbilitySpec = _granted(
		func _priced(probe: ProbeAbility) -> void:
			probe.costs = [authored] as Array[GameplayAbilityCost]
	)

	authored.amount.value = 999.0

	var captured: GameplayAbilityCost = spec.definition.costs[0]
	assert_almost_eq(
		captured.amount.value, 10.0, 0.0001, "the grant kept the price it was given"
	)


## The same for the nested Resources of a query and of a cooldown.
##
## Two more places the shallow copy reached through: a tag query holds its
## expression, and a cooldown effect holds its components, so editing either
## rewrote what a granted ability was gated by or how long it waited.
func test_editing_a_query_or_a_cooldown_after_the_grant_changes_nothing() -> void:
	var gate: GameplayTagQuery = _tag_query(BLESSED)
	var cooldown: GameplayEffect = _cooldown()
	var spec: GameplayAbilitySpec = _granted(
		func _gated(probe: ProbeAbility) -> void:
			probe.activation_required_query = gate
			probe.cooldown_effect = cooldown
	)

	gate.root.tags = [CURSED] as Array[StringName]
	cooldown.duration = 999.0

	var captured_gate: GameplayTagQuery = spec.definition.activation_required_query
	assert_eq(
		Array(captured_gate.root.tags),
		[BLESSED],
		"the gate is still the one the grant read"
	)
	assert_almost_eq(
		spec.definition.cooldown_effect.duration,
		5.0,
		0.0001,
		"and the cooldown still waits what it was given"
	)


## Two grants of one authored ability do not share the objects they captured.
##
## Otherwise the deep copy buys nothing at the second grant: editing through
## either snapshot would move the other, which is the same bug one level along.
func test_two_grants_do_not_share_the_resources_they_captured() -> void:
	var authored: GameplayAbilityCost = _cost(10.0)
	var configure: Callable = func _priced(probe: ProbeAbility) -> void:
		probe.costs = [authored] as Array[GameplayAbilityCost]

	var first: GameplayAbilitySpec = _granted(configure)
	var second: GameplayAbilitySpec = _granted(configure)

	var one: GameplayAbilityCost = first.definition.costs[0]
	var other: GameplayAbilityCost = second.definition.costs[0]
	assert_ne(one, other, "two grants, two cost objects")
	assert_ne(one.amount, other.amount, "down to the nested magnitude")

	one.amount.value = 42.0
	assert_almost_eq(
		other.amount.value, 10.0, 0.0001, "so moving one leaves the other alone"
	)


## One Resource listed twice is still one object after the copy.
##
## The aliasing is load-bearing, not incidental: a commit decides that a
## cooldown listed as both its own and a shared one is applied once by comparing
## the objects. Two separate copies would start the same cooldown twice.
func test_a_cooldown_listed_twice_stays_one_object_in_the_snapshot() -> void:
	var shared: GameplayEffect = _cooldown()
	var spec: GameplayAbilitySpec = _granted(
		func _cooled(probe: ProbeAbility) -> void:
			probe.cooldown_effect = shared
			probe.shared_cooldown_effects = [shared] as Array[GameplayEffect]
	)

	assert_eq(
		spec.definition.cooldown_effect,
		spec.definition.shared_cooldown_effects[0],
		"listed twice, captured once"
	)
	assert_ne(spec.definition.cooldown_effect, shared, "and still a copy of the author's")
#endregion


#region What must not be published
## An application whose aggregate cannot be composed publishes nothing.
##
## B15. Two contributions that each resolve finitely and overflow together: the
## composition produced infinity, and by the time anything noticed, both were
## already registered. The attribute then failed to recompose for every other
## effect on it too, so one bad buff took the whole aggregate down.
func test_an_application_that_would_overflow_the_aggregate_is_refused_whole() -> void:
	target.set_base(ATTACK, 0.0)
	var huge: float = 1e308
	var first: GameplayEffect = Factory.infinite([Factory.add(ATTACK, huge)])
	var second: GameplayEffect = Factory.infinite([Factory.add(ATTACK, huge)])

	assert_not_null(Factory.apply(target.asc, first), "the first one fits")
	var before: int = target.asc.effects.active_count()

	var overflowing: GameplayEffectApplicationResult = Factory.apply_result(
		target.asc, second
	)

	assert_false(overflowing.is_ok(), "the second one is refused")
	assert_eq(
		target.asc.effects.active_count(), before, "and nothing was registered for it"
	)
	assert_true(
		is_finite(target.current_of(ATTACK)),
		"the attribute still composes: %s" % target.current_of(ATTACK)
	)
#endregion


#region When a source's tags were read
## The snapshot is what the source had when it was applied, and nothing after.
##
## B16. The capture was guarded by `source_asc == null`, which answers a
## different question than the one it was standing in for: an application that
## already knew its source - which is what the component's own entry point
## produces - skipped the guard and never snapshotted anything at all.
##
## Both halves are asserted together because either alone is satisfied by the
## wrong thing: a snapshot that captured nothing has no CURSED in it either, and
## one that re-reads the world on every question has BLESSED in it forever.
func test_a_source_snapshot_is_what_it_had_and_not_what_it_gained() -> void:
	source.asc.tags.add(BLESSED)
	var effect: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 1.0)])

	# Through the component's own entry point, which sets `spec.source_asc`
	# before captures are prepared.
	var active: ActiveGameplayEffect = target.asc.apply_gameplay_effect(effect, source.asc)
	source.asc.tags.add(CURSED)

	assert_true(
		active.spec.source_tags_snapshot.has(BLESSED),
		"the snapshot carries what the source had: %s" % [active.spec.source_tags_snapshot]
	)
	assert_false(
		active.spec.source_tags_snapshot.has(CURSED),
		"and nothing it gained afterwards: %s" % [active.spec.source_tags_snapshot]
	)


## Preparing captures twice does not read the source's tags twice.
##
## B16. The capture was guarded by `source_asc == null`, which answers a
## different question: an application whose source was resolved late captured
## nothing, and one with no source at all re-captured on every later call. Asked
## as "have these been captured", both come out right.
func test_a_second_capture_does_not_re_read_the_source() -> void:
	source.asc.tags.add(BLESSED)
	var effect: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 1.0)])
	var active: ActiveGameplayEffect = target.asc.apply_gameplay_effect(
		effect, source.asc
	)
	var taken: Array[StringName] = active.spec.source_tags_snapshot.duplicate()

	source.asc.tags.add(CURSED)
	active.spec.prepare_captures(source.asc)

	assert_eq(
		Array(active.spec.source_tags_snapshot),
		Array(taken),
		"the second call read nothing new"
	)


## And a copy made for another application carries the same answer.
##
## Otherwise the copy re-captures at whatever the world looks like when it is
## made, and one application ends up carrying two different ideas of what its
## source was.
func test_an_application_copy_carries_the_capture_that_was_already_taken() -> void:
	source.asc.tags.add(BLESSED)
	var effect: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 1.0)])
	var active: ActiveGameplayEffect = target.asc.apply_gameplay_effect(
		effect, source.asc
	)

	source.asc.tags.add(CURSED)
	var copy: GameplayEffectSpec = active.spec.create_application_copy()
	copy.prepare_captures(source.asc)

	assert_true(copy.source_tags_snapshot.has(BLESSED), "it kept what was captured")
	assert_false(
		copy.source_tags_snapshot.has(CURSED),
		"and did not capture again: %s" % [copy.source_tags_snapshot]
	)
#endregion
