## What the scheduler owes when the world changes underneath it.
##
## Every assertion here is about a frame in which something moved: an effect
## expired halfway through the delta it was given, a callback removed the effect
## that was ticking, a callback removed a *different* effect and shifted every
## index after it, or an effect was inhibited between two ticks of the same
## frame.
##
## The old walk could not survive any of them. It iterated the live array by
## index, so a removal renumbered what it was about to visit; it created a
## frame's worth of tick debt before asking how much of that frame the effect
## was alive for, so a long delta invented ticks after expiry; and it held a
## reference across a callback that could have removed the object it pointed at.
##
## So the shape is: identity, never an index. Nothing is visited unless it is
## still registered at the moment it is about to be visited, and no tick is
## created for time the effect was not alive.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const CueProbe = preload("res://test/fixtures/cue_probe.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")

## Counted on `attack` rather than on `health`, and upward.
##
## The suite's health is clamped to max_health both ways, so a test that
## counted 200 ticks against it would stop at zero and report the clamp instead
## of the scheduler. Attack is only floored, so counting up from nothing has no
## ceiling to hit and the number read back IS the number of ticks that ran.
const COUNTER: StringName = &"attack"

## One point per tick.
const PER_TICK: float = 1.0

const BLEED_CUE: StringName = &"Cue.Bleed"
const BLED: StringName = &"Event.Bled"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var manager: CueManagerScript = null


func before_each() -> void:
	_open()
	manager = asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript
	CueProbe.install(manager, BLEED_CUE)


## A fresh entity with nothing on its counter.
##
## Called again by the table-driven test: `before_each` runs once per test, so a
## row that read the previous row's attribute would be reading history.
func _open() -> void:
	fixture = Fixture.create("Ticker")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	# Driven by hand: a frame rate must never decide whether an assertion holds.
	asc.set_process(false)
	asc.set_attribute_base(COUNTER, 0.0)


func after_each() -> void:
	CueProbe.uninstall(manager, BLEED_CUE)
	fixture = null
	asc = null
	manager = null


#region Counting ticks by what they did
## How many periodic ticks have run, read off the attribute they wrote.
##
## Counted from the world rather than from a signal on purpose: a tick that
## announced itself and wrote nothing, or wrote and announced twice, is exactly
## the failure being looked for.
func _ticks() -> int:
	return int(roundf(asc.get_attribute_base(COUNTER)))


func _bleed(seconds: float, period: float) -> GameplayEffect:
	var modifiers: Array[GameplayEffectModifier] = [Factory.add(COUNTER, PER_TICK)]
	return Factory.periodic(modifiers, seconds, period)


## The same effect, announcing each tick through a cue and an event.
func _noisy_bleed(seconds: float, period: float) -> GameplayEffect:
	return Factory.with_events(
		Factory.with_periodic_cues(_bleed(seconds, period), [BLEED_CUE]), [BLED]
	)


func _cues() -> int:
	return CueProbe.executions(manager, asc.get_effect_target(), BLEED_CUE)
#endregion


#region A finite effect cannot tick after it is over
## A second of life, paid at three different frame rates.
##
## B01. The old walk asked for a frame's worth of tick debt before asking how
## much of the frame the effect was alive for, so a delta longer than the
## remaining lifetime bought ticks with time the effect did not have.
##
## The rows are the point rather than any one of them. One long frame and four
## short ones are the same second of game time, and a scheduler whose answer
## depends on frame rate is a scheduler nobody can reproduce a bug in. The last
## row owes more ticks in one frame than the per-update cap allows: the cap is a
## work limit, not a lifetime limit, so the debt already due inside the second
## gets paid over later frames and not one tick more is invented for the time
## after it ended.
##
##     [what it is, lifetime, period, frames, delta, ticks owed]
const PAID: Array = [
	["one two-second frame", 1.0, 0.5, 1, 2.0, 2],
	["four half-second frames", 1.0, 0.5, 4, 0.5, 2],
	["a period far shorter than the work cap", 1.0, 0.005, 12, 1.0, 200],
]


func test_a_finite_effect_ticks_for_its_lifetime_and_never_past_it() -> void:
	var checked: int = 0
	for row: Array in PAID:
		var described: String = row[0]
		var lifetime: float = row[1]
		var period: float = row[2]
		var frames: int = row[3]
		var delta: float = row[4]
		var owed: int = row[5]

		# A fresh entity per row: `before_each` runs once for the whole test, so
		# a row reading the previous row's attribute would be reading history.
		_open()
		asc.apply_gameplay_effect(_bleed(lifetime, period))

		for _frame: int in frames:
			asc.scheduler.advance_time(delta)

		assert_eq(_ticks(), owed, "%s: %d ticks" % [described, owed])
		assert_eq(asc.effects.active_count(), 0, "%s: and then it is over" % described)
		checked += 1
	assert_eq(checked, PAID.size(), "every frame rate was paid")
#endregion


#region A callback that changes the world mid-frame
## An effect removed by the very signal its first tick raised does not tick again.
##
## B02. The scheduler used to hold the object across the callback and go on
## paying its backlog, so a listener that cancelled a bleed watched it bleed
## four more times. The cue and the event are asserted too: a tick that did not
## happen must not be announced, and "the attribute stopped changing" would be
## true even if it were.
func test_removing_an_effect_from_its_own_tick_stops_it_there() -> void:
	var active: ActiveGameplayEffect = asc.apply_gameplay_effect(_noisy_bleed(10.0, 0.1))
	var events: Array[StringName] = []
	asc.gameplay_event_received.connect(
		func _heard(event: GameplayEventData) -> void:
			events.append(event.event_tag)
	)
	asc.gameplay_effect_executed.connect(
		func _executed(_spec: GameplayEffectSpec, ticked: ActiveGameplayEffect) -> void:
			asc.remove_active_effect(ticked)
	)

	asc.scheduler.advance_time(1.0)

	assert_eq(_ticks(), 1, "the tick that removed it ran, and nothing after it")
	assert_eq(asc.effects.active_count(), 0, "it really is gone")
	assert_true(active != null, "and the object it was is still safe to hold")
	assert_eq(_cues(), 0, "no cue was played after the removal")
	assert_eq(events.size(), 0, "and no event was dispatched after it")


## Removing a different effect mid-frame does not skip or repeat a neighbour.
##
## B03. The walk was by index into the live array, so removing an earlier
## element renumbered everything after it: one effect got visited twice and
## another not at all, depending on which way the removal shifted them.
##
## The visit order is recorded rather than counted, because "two ticks happened"
## is also what a walk that visited one effect twice and skipped the other would
## report - and that is the actual failure.
func test_an_effect_that_removes_another_leaves_every_neighbour_visited_once() -> void:
	var first: ActiveGameplayEffect = asc.apply_gameplay_effect(_bleed(10.0, 1.0))
	var second: ActiveGameplayEffect = asc.apply_gameplay_effect(_bleed(10.0, 1.0))
	var third: ActiveGameplayEffect = asc.apply_gameplay_effect(_bleed(10.0, 1.0))
	assert_eq(asc.effects.active_count(), 3, "three of them to start")

	# An Array, because a GDScript lambda captures a local by value: a `bool`
	# set inside one is set on the copy, and the test would be asserting about a
	# variable nothing ever wrote.
	var visited: Array[ActiveGameplayEffect] = []
	asc.gameplay_effect_executed.connect(
		func _executed(_spec: GameplayEffectSpec, ticked: ActiveGameplayEffect) -> void:
			visited.append(ticked)
			if visited.size() == 1:
				asc.remove_active_effect(first)
	)

	asc.scheduler.advance_time(1.0)

	assert_eq(visited.size(), 2, "two effects were visited: %s" % [visited.size()])
	assert_false(visited.has(first), "the one taken out mid-frame never ticked")
	assert_true(visited.has(second), "the neighbour that survived did")
	assert_true(visited.has(third), "and so did the other one")
	assert_eq(_ticks(), 2, "which is exactly the work that was done")
	assert_eq(asc.effects.active_count(), 2, "and two are left")


## An effect inhibited by an earlier tick of the same frame stops ticking at once.
func test_inhibiting_an_effect_mid_frame_stops_its_remaining_ticks() -> void:
	var active: ActiveGameplayEffect = asc.apply_gameplay_effect(_bleed(10.0, 0.1))
	asc.gameplay_effect_executed.connect(
		func _executed(_spec: GameplayEffectSpec, ticked: ActiveGameplayEffect) -> void:
			asc.effects.inhibition.set_inhibited(ticked, true)
	)

	asc.scheduler.advance_time(1.0)

	assert_eq(_ticks(), 1, "the tick that inhibited it, and no more")
	assert_true(active.inhibited, "and it is inhibited rather than removed")
#endregion


#region Turns
## The curse both inhibition tests are about.
func _curse(turns: int, at_turn_start: bool) -> GameplayEffect:
	var modifiers: Array[GameplayEffectModifier] = [Factory.add(COUNTER, PER_TICK)]
	var made: GameplayEffect = Factory.turn_based(modifiers, turns, 1.0)
	made.tick_on_turn_start = at_turn_start
	return made


## What a turn-based effect does while it is inhibited, and once it is not.
##
## B04. The turn path never asked. Inhibition is about what an effect *does*,
## not about whether time passes for it, so the duration has to run down either
## way - otherwise inhibiting a three-turn curse makes it last forever. Both
## rows assert the pair, because "it did not tick" alone is also what a curse
## frozen in time would report.
##
##     [what it is, turns declared, one bool per turn played, ticks, turns left]
##
## A step is `true` to inhibit before playing that turn and `false` to allow it,
## so a row reads as the sequence of turns somebody actually played.
const TURNS_PLAYED: Array = [
	["inhibited for the turn it was given", 2, [true], 0, 1],
	["inhibited, then allowed to act", 3, [true, false], 1, 1],
]


func test_an_inhibited_turn_effect_spends_the_turn_without_acting() -> void:
	var checked: int = 0
	for row: Array in TURNS_PLAYED:
		var described: String = row[0]
		var turns: int = row[1]
		var steps: Array = row[2]
		var owed: int = row[3]
		var left: int = row[4]

		_open()
		var active: ActiveGameplayEffect = asc.apply_gameplay_effect(_curse(turns, true))
		for inhibited: bool in steps:
			asc.effects.inhibition.set_inhibited(active, inhibited)
			asc.advance_turn()

		assert_eq(_ticks(), owed, "%s: %d tick(s)" % [described, owed])
		assert_eq(
			active.spec.remaining_turns,
			left,
			"%s: the turns were spent either way" % described
		)
		checked += 1
	assert_eq(checked, TURNS_PLAYED.size(), "every sequence was played")


## `tick_on_turn_start = false` means the tick belongs to the end of the turn.
##
## Both halves are asserted, because "it ticked once" is true of either reading
## and says nothing. What separates them is the last turn: an end-of-turn tick
## on a one-turn effect still runs, and then the effect expires.
func test_an_end_of_turn_effect_ticks_after_the_turn_is_spent() -> void:
	asc.apply_gameplay_effect(_curse(1, false))

	asc.advance_turn()

	assert_eq(_ticks(), 1, "its one turn ended, so it ticked")
	assert_eq(asc.effects.active_count(), 0, "and then it was over")
#endregion
