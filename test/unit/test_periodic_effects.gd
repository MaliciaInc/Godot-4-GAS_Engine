## Timers: periodic ticks, duration expiry and turns.
##
## Ticks derive from elapsed time, not from a countdown that gets reset. A frame
## long enough to span three periods owes three ticks and pays all three from
## their theoretical indices. An accumulator pays one and drops two, and the
## drift compounds for the effect's whole life.
##
## Real time and turns are separate axes: a hundred frames advance a turn-based
## effect by exactly zero turns.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const HEALTH: StringName = &"health"
const ATTACK: StringName = &"attack"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Ticker")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	# The ASC ticks from _process. The tests drive the scheduler directly so a
	# frame rate never decides whether an assertion holds.
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null
	restore_error_reporting()


## Declare that the engine is expected to report an error in this test.
##
## The engine refuses invalid input loudly, which is right: a caller passing a
## bad modifier index or a negative delta has a bug. GUT counts any push_error
## during a test as a failure, so a test that deliberately provokes one says so
## here. Lowering the engine's own severity to keep the suite quiet would trade
## a real diagnostic for a green tick.
func expect_engine_error() -> void:
	GutUtils.get_error_tracker().treat_push_error_as = GutUtils.TREAT_AS.NOTHING


## Restore the default so the next test still fails on an unexpected error.
func restore_error_reporting() -> void:
	GutUtils.get_error_tracker().treat_push_error_as = GutUtils.TREAT_AS.FAILURE


func _tick(delta: float) -> void:
	asc.scheduler.advance_time(delta)


#region Tick accounting
func test_less_than_one_period_owes_nothing() -> void:
	fixture.set_base(HEALTH, 50.0)
	Factory.apply(asc, Factory.infinite_periodic([Factory.add(HEALTH, -1.0)], 1.0))
	_tick(0.4)
	assert_almost_eq(fixture.base_of(HEALTH), 50.0, TOLERANCE, "no tick yet")


func test_the_first_tick_lands_exactly_at_one_period() -> void:
	fixture.set_base(HEALTH, 50.0)
	Factory.apply(asc, Factory.infinite_periodic([Factory.add(HEALTH, -1.0)], 1.0))
	_tick(0.4)
	_tick(0.6)
	assert_almost_eq(fixture.base_of(HEALTH), 49.0, TOLERANCE, "one tick at t=1.0")


func test_a_long_frame_pays_every_tick_it_owes() -> void:
	fixture.set_base(HEALTH, 50.0)
	var active: ActiveGameplayEffect = Factory.apply(
		asc, Factory.infinite_periodic([Factory.add(HEALTH, -1.0)], 1.0)
	)
	# One 3.2 s step from zero owes ticks 1, 2 and 3. A countdown would pay one.
	_tick(3.2)
	assert_almost_eq(fixture.base_of(HEALTH), 47.0, TOLERANCE, "three ticks paid")
	assert_almost_eq(active.elapsed_time, 3.2, TOLERANCE, "the clock kept the remainder")
	assert_eq(active.completed_ticks, 3, "and knows how many it has paid")


func test_many_small_frames_do_not_drift() -> void:
	fixture.set_base(HEALTH, 100.0)
	Factory.apply(asc, Factory.infinite_periodic([Factory.add(HEALTH, -1.0)], 1.0))
	# Ten steps of 0.1 should be exactly one tick, not zero and not two. A
	# repeatedly-subtracted accumulator accumulates float error here.
	for _step: int in 100:
		_tick(0.1)
	assert_almost_eq(fixture.base_of(HEALTH), 90.0, TOLERANCE, "ten ticks over ten seconds")
#endregion


#region Invalid updates
func test_a_negative_delta_is_refused() -> void:
	fixture.set_base(HEALTH, 50.0)
	Factory.apply(asc, Factory.infinite_periodic([Factory.add(HEALTH, -1.0)], 1.0))
	expect_engine_error()
	_tick(-5.0)
	# Running the catch-up loop backwards is not a smaller mistake than crashing.
	assert_almost_eq(fixture.base_of(HEALTH), 50.0, TOLERANCE, "nothing happened")


func test_a_non_finite_delta_is_refused() -> void:
	fixture.set_base(HEALTH, 50.0)
	Factory.apply(asc, Factory.infinite_periodic([Factory.add(HEALTH, -1.0)], 1.0))
	expect_engine_error()
	_tick(INF)
	assert_almost_eq(fixture.base_of(HEALTH), 50.0, TOLERANCE, "no infinite catch-up loop")
#endregion


#region Duration
func test_a_duration_effect_expires_and_reverts() -> void:
	fixture.set_base(ATTACK, 10.0)
	Factory.apply(asc, Factory.duration([Factory.add(ATTACK, 5.0)], 2.0))
	assert_almost_eq(fixture.current_of(ATTACK), 15.0, TOLERANCE)

	_tick(1.0)
	assert_almost_eq(fixture.current_of(ATTACK), 15.0, TOLERANCE, "still running")

	_tick(1.0)
	assert_eq(asc.get_active_effects().size(), 0, "expired")
	assert_almost_eq(fixture.current_of(ATTACK), 10.0, TOLERANCE, "reverted")


func test_expiry_announces_the_removal_once() -> void:
	Factory.apply(asc, Factory.duration([Factory.add(ATTACK, 5.0)], 1.0))
	watch_signals(asc)
	_tick(1.5)
	assert_signal_emit_count(asc, "active_effect_removed", 1)
#endregion


#region Turns
func test_frames_do_not_advance_turns() -> void:
	Factory.apply(asc, Factory.turn_based([Factory.add(ATTACK, 5.0)], 3))
	for _frame: int in 100:
		_tick(1.0)
	assert_eq(asc.get_active_effects().size(), 1, "a hundred frames spent zero turns")


func test_one_advance_spends_one_turn() -> void:
	var active: ActiveGameplayEffect = Factory.apply(asc, Factory.turn_based([Factory.add(ATTACK, 5.0)], 3))
	asc.advance_turn()
	assert_eq(active.spec.remaining_turns, 2, "exactly one")


func test_advancing_three_turns_spends_three() -> void:
	var active: ActiveGameplayEffect = Factory.apply(asc, Factory.turn_based([Factory.add(ATTACK, 5.0)], 5))
	asc.advance_turn(3)
	assert_eq(active.spec.remaining_turns, 2, "exactly three")


func test_a_turn_based_effect_expires_on_its_last_turn() -> void:
	fixture.set_base(ATTACK, 10.0)
	Factory.apply(asc, Factory.turn_based([Factory.add(ATTACK, 5.0)], 2))
	asc.advance_turn(2)
	assert_eq(asc.get_active_effects().size(), 0, "spent")
	assert_almost_eq(fixture.current_of(ATTACK), 10.0, TOLERANCE, "reverted")


func test_a_turn_based_periodic_ticks_once_per_turn() -> void:
	fixture.set_base(HEALTH, 50.0)
	var poison: GameplayEffect = Factory.turn_based([Factory.add(HEALTH, -3.0)], 3, 1.0)
	poison.tick_on_turn_start = true
	Factory.apply(asc, poison)

	asc.advance_turn(3)
	assert_almost_eq(fixture.base_of(HEALTH), 41.0, TOLERANCE, "three ticks of three damage")
	assert_eq(asc.get_active_effects().size(), 0, "and three turns of duration spent")
#endregion


#region Periodic effects mutate the base
func test_a_periodic_effect_contributes_nothing_to_the_aggregator() -> void:
	fixture.set_base(HEALTH, 50.0)
	var active: ActiveGameplayEffect = Factory.apply(
		asc, Factory.infinite_periodic([Factory.add(HEALTH, -1.0)], 1.0)
	)
	# One effect cannot be both periodic and a persistent
	# contributor. A contributing DoT would compound its own damage every tick.
	assert_false(active.has_contributions(), "no contributions registered")

	_tick(1.0)
	assert_almost_eq(fixture.base_of(HEALTH), 49.0, TOLERANCE, "the tick wrote the base")
	assert_almost_eq(fixture.current_of(HEALTH), 49.0, TOLERANCE)


func test_removing_a_periodic_effect_does_not_undo_its_ticks() -> void:
	fixture.set_base(HEALTH, 50.0)
	var poison: ActiveGameplayEffect = Factory.apply(
		asc, Factory.infinite_periodic([Factory.add(HEALTH, -1.0)], 1.0)
	)
	_tick(3.0)
	asc.remove_active_effect(poison)
	# Damage already dealt is durable. Curing a poison does not refund it.
	assert_almost_eq(fixture.base_of(HEALTH), 47.0, TOLERANCE, "the damage stays")
#endregion
