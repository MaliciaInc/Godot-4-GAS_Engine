## A deterministic combinatorial regression over the whole engine.
##
## Not fuzzing. A fixed seed drives a long, reproducible sequence of operations,
## and after every single one the same invariants are checked. The value is in
## the combinations: a bug that needs "apply, refresh, tick, remove, set base,
## remove again" to appear will not be found by any test written to describe one
## behaviour, because nobody thinks to write that sequence down.
##
## The strongest invariant is the last: the stored current value must equal what
## a fresh evaluation from base plus active contributions produces. Any drift
## between the aggregator's cache and its own arithmetic is caught the moment it
## happens, whatever caused it.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const SEED: int = 20260830
const OPERATIONS: int = 240
const TOLERANCE: float = 0.001

const ATTACK: StringName = &"attack"
const HEALTH: StringName = &"health"
const MANA: StringName = &"mana"
const DEFENSE: StringName = &"defense"
const BUFFED: StringName = &"Status.Buffed"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var rng: RandomNumberGenerator = null
var tracked: Array[ActiveGameplayEffect] = []


func before_each() -> void:
	fixture = Fixture.create("Subject")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	rng = RandomNumberGenerator.new()
	rng.seed = SEED
	tracked = []


func after_each() -> void:
	fixture = null
	asc = null
	rng = null
	tracked = []


#region The run
func test_a_long_deterministic_sequence_holds_every_invariant() -> void:
	for step: int in OPERATIONS:
		_perform(step % 12)
		_assert_invariants(step)
	pass_test("%d operations, invariants held after each" % OPERATIONS)


func test_the_sequence_is_reproducible() -> void:
	var first: Array[float] = _run_and_snapshot()
	before_each()
	var second: Array[float] = _run_and_snapshot()
	# A regression nobody can reproduce is a rumour. Same seed, same ending.
	assert_eq(first.size(), second.size())
	for index: int in first.size():
		assert_almost_eq(second[index], first[index], TOLERANCE, "value %d" % index)


func _run_and_snapshot() -> Array[float]:
	for step: int in OPERATIONS:
		_perform(step % 12)
	return [
		fixture.base_of(ATTACK), fixture.current_of(ATTACK),
		fixture.base_of(HEALTH), fixture.current_of(HEALTH),
		fixture.base_of(MANA), fixture.current_of(MANA),
	] as Array[float]
#endregion


#region Operations
func _perform(kind: int) -> void:
	match kind:
		0: _set_base()
		1: _instant_add()
		2: _duration_add()
		3: _duration_multiply()
		4: _valid_divide()
		5: _override()
		6: _remove_one()
		7: _refresh()
		8: _free_stack()
		9: _tick_periodic()
		10: _advance_turn()
		11: _maybe_cleanup()


func _attribute() -> StringName:
	var pool: Array[StringName] = [ATTACK, HEALTH, MANA, DEFENSE]
	return pool[rng.randi_range(0, pool.size() - 1)]


func _magnitude() -> float:
	return snappedf(rng.randf_range(-20.0, 20.0), 0.25)


func _track(active: ActiveGameplayEffect) -> void:
	if active != null:
		tracked.append(active)


func _set_base() -> void:
	asc.set_attribute_base(_attribute(), snappedf(rng.randf_range(0.0, 120.0), 0.5))


func _instant_add() -> void:
	Factory.apply(asc, Factory.instant([Factory.add(_attribute(), _magnitude())]))


func _duration_add() -> void:
	_track(Factory.apply(asc, Factory.duration([Factory.add(_attribute(), _magnitude())], 3.0)))


func _duration_multiply() -> void:
	# Kept away from zero: a zero multiplier is legal but collapses the attribute
	# and makes later assertions uninformative rather than wrong.
	var factor: float = snappedf(rng.randf_range(0.5, 2.5), 0.25)
	_track(Factory.apply(asc, Factory.duration([Factory.multiply(_attribute(), factor)], 4.0)))


func _valid_divide() -> void:
	var divisor: float = snappedf(rng.randf_range(1.0, 4.0), 0.25)
	_track(Factory.apply(asc, Factory.infinite([Factory.divide(_attribute(), divisor)])))


func _override() -> void:
	_track(Factory.apply(asc, Factory.infinite([Factory.override(_attribute(), _magnitude())])))


func _remove_one() -> void:
	tracked = tracked.filter(func(e: ActiveGameplayEffect) -> bool: return e != null)
	if tracked.is_empty():
		return
	var index: int = rng.randi_range(0, tracked.size() - 1)
	asc.remove_active_effect(tracked[index])
	tracked.remove_at(index)


func _refresh() -> void:
	var effect: GameplayEffect = Factory.refreshing(
		Factory.granting(
			Factory.duration([Factory.add(ATTACK, _magnitude())], 5.0), [BUFFED] as Array[StringName]
		)
	)
	_track(Factory.apply(asc, effect))


func _free_stack() -> void:
	var effect: GameplayEffect = Factory.duration([Factory.add(DEFENSE, _magnitude())], 6.0)
	_track(Factory.apply(asc, effect))
	_track(Factory.apply(asc, effect))


func _tick_periodic() -> void:
	_track(Factory.apply(asc, Factory.infinite_periodic([Factory.add(HEALTH, -1.0)], 1.0)))
	asc.scheduler.advance_time(snappedf(rng.randf_range(0.0, 2.5), 0.25))


func _advance_turn() -> void:
	_track(Factory.apply(asc, Factory.turn_based([Factory.add(MANA, _magnitude())], 2)))
	asc.advance_turn(rng.randi_range(1, 2))


func _maybe_cleanup() -> void:
	if rng.randf() < 0.15:
		asc.cleanup()
		tracked.clear()
#endregion


#region Invariants
func _assert_invariants(step: int) -> void:
	var where: String = " after step %d" % step
	for name: StringName in asc.attributes.all_attribute_names():
		var attribute: AttributeData = asc.attributes.find(name)
		assert_true(is_finite(attribute.base_value), "base of %s is finite%s" % [name, where])
		assert_true(is_finite(attribute.current_value), "current of %s is finite%s" % [name, where])

	_assert_specs_are_unshared(where)
	_assert_current_matches_a_fresh_evaluation(where)
	_assert_removed_effects_contribute_nothing(where)


func _assert_specs_are_unshared(where: String) -> void:
	var seen: Array[GameplayEffectSpec] = []
	for active: ActiveGameplayEffect in asc.get_active_effects():
		assert_not_null(active.spec, "every active effect has a spec" + where)
		assert_false(seen.has(active.spec), "no two active effects share a spec" + where)
		seen.append(active.spec)


## The cache must equal the arithmetic. This is the invariant that catches a
## drift no individual behaviour test would name.
func _assert_current_matches_a_fresh_evaluation(where: String) -> void:
	for name: StringName in asc.attributes.all_attribute_names():
		var evaluation: AttributeEvaluationResult = asc.attributes.evaluate(name)
		if not evaluation.is_ok():
			continue
		assert_almost_eq(
			asc.attributes.get_current_value(name),
			evaluation.final_value,
			TOLERANCE,
			"stored current of %s equals a fresh evaluation%s" % [name, where]
		)


## Every contribution in the aggregator must belong to an effect that is still
## active. A removal that dropped the effect but left its contribution would
## show up here as a stat that never comes back down.
func _assert_removed_effects_contribute_nothing(where: String) -> void:
	var live_orders: Array[int] = []
	for active: ActiveGameplayEffect in asc.get_active_effects():
		live_orders.append(active.application_order)

	for name: StringName in asc.attributes.all_attribute_names():
		for contribution: AttributeModifierContribution in asc.attributes.contributions_for(name):
			assert_true(
				live_orders.has(contribution.application_order),
				"contribution to %s belongs to a live effect%s" % [name, where]
			)
#endregion
