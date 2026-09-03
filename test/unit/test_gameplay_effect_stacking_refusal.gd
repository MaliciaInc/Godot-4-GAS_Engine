## A stack whose expiration cannot be re-evaluated.
##
## The three expiration policies are covered next door. This is the case none of
## them cover: the policy says the stack survives, and the re-evaluation that
## has to happen for it to survive refuses.
##
## Two claims, and the framework already makes the first one everywhere else: a
## refused operation leaves no partial mutations. `_settle_expiring` sets
## `spec.stack_count` to the count it is about to settle at - the magnitude is
## scaled by it - and then evaluates. The spec belongs to an effect that stays
## on the component, so a refusal after that point used to leave the receipt
## saying one count and the spec saying another.
##
## The second is quieter and worse. The scheduler expires whatever has run out
## of time on every update, so an effect left at zero that cannot settle was
## asked again on the next frame, and the frame after that, for as long as it
## lived - which was for ever, because nothing here takes it down.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const ATTACK: StringName = &"attack"

var target: ASCFixture = null


func before_each() -> void:
	target = Fixture.create("Target")
	add_child_autofree(target.owner)


func after_each() -> void:
	target = null


## An operation outside the enum, set after the stacks are already up.
##
## The evaluator names this case itself: "a resource written by another
## version, or set from code". It is the controllable stand-in for a whole
## class - a captured source that has gone away, an attribute that no longer
## exists, a divisor that has reached zero - where a spec that evaluated
## perfectly at application does not evaluate now.
const OUTSIDE_THE_ENUM: int = 99


func _stack_that_stops_evaluating() -> ActiveGameplayEffect:
	var effect: GameplayEffect = Factory.with_stack_expiration_policy(
		Factory.stacked(
			Factory.duration([Factory.add(ATTACK, 5.0)], 10.0),
			GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0, true
		),
		GameplayEffect.StackExpirationPolicy.REMOVE_SINGLE_STACK_AND_REFRESH_DURATION
	)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	assert_eq(active.stack_count, 3, "three stacks, all applied cleanly")

	effect.modifiers[0].operation = OUTSIDE_THE_ENUM
	return active


## A refused expiration leaves the stack exactly as it found it.
##
## `_settle_expiring` sets `spec.stack_count` to the count it is about to
## settle at, because the magnitude is scaled by it - and then evaluates. The
## spec it is mutating belongs to an effect that stays on the component, so a
## refusal after that point leaves the receipt saying one thing and the spec
## saying another. Nothing downstream can tell which is right.
func test_a_refused_expiration_leaves_the_count_it_found() -> void:
	var active: ActiveGameplayEffect = _stack_that_stops_evaluating()

	target.asc.effects.expire(active)

	assert_eq(active.stack_count, 3, "the receipt kept its count")
	assert_eq(
		active.spec.stack_count, active.stack_count,
		"and the spec agrees with it: %d against %d" % [
			active.spec.stack_count, active.stack_count
		]
	)


## And it does not leave the clock expired.
##
## The scheduler expires whatever has run out of time, every update. An effect
## left at zero that refuses to settle is asked again on the next frame, and the
## one after that - a refusal per frame, for as long as the effect lives, which
## is for ever because nothing takes it down.
func test_a_refused_expiration_does_not_ask_again_every_frame() -> void:
	var active: ActiveGameplayEffect = _stack_that_stops_evaluating()
	active.time_remaining = 0.0

	target.asc.effects.expire(active)

	assert_true(
		target.asc.effects.active_effects().has(active), "the effect is still there"
	)
	assert_gt(active.time_remaining, 0.0, "with time on its clock again")

	var refusals: int = target.asc.effects.refusal_log.recent().size()
	target.asc.scheduler.advance_time(0.016)
	assert_eq(
		target.asc.effects.refusal_log.recent().size(), refusals,
		"and the next frame does not produce another refusal"
	)
