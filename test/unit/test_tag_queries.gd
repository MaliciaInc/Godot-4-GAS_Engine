## Tag semantics: reference counting, exact matching and hierarchy.
##
## Two upstream contracts were wrong and both are pinned here:
##
##   has_all_tags([]) returned false, which made "no requirements" the strictest
##   requirement an ability could have.
##
##   has_tag matched by bare prefix, so `Damage.Fire` matched `Damage.Firestorm`
##   and `A` matched `AB`.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const STATUS: StringName = &"Status"
const STUNNED: StringName = &"Status.Stunned"
const BURNING: StringName = &"Status.Burning"
const DAMAGE_FIRE: StringName = &"Damage.Fire"
const DAMAGE_FIRESTORM: StringName = &"Damage.Firestorm"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Tagged")
	add_child_autofree(fixture.owner)
	asc = fixture.asc


func after_each() -> void:
	fixture = null
	asc = null


#region has_all_tags
func test_an_empty_requirement_is_satisfied() -> void:
	var nothing: Array[StringName] = []
	# Vacuously true: the set contains no tag that is missing. Returning false
	# here meant an ability with no requirements could never activate.
	assert_true(asc.has_all_tags(nothing), "no requirements means nothing to fail")


func test_one_present_requirement_is_satisfied() -> void:
	asc.add_tag(STUNNED)
	assert_true(asc.has_all_tags([STUNNED] as Array[StringName]))


func test_one_missing_requirement_is_not_satisfied() -> void:
	assert_false(asc.has_all_tags([STUNNED] as Array[StringName]))


func test_all_present_requirements_are_satisfied() -> void:
	asc.add_tag(STUNNED)
	asc.add_tag(BURNING)
	assert_true(asc.has_all_tags([STUNNED, BURNING] as Array[StringName]))


func test_one_missing_out_of_several_fails_the_whole_query() -> void:
	asc.add_tag(STUNNED)
	assert_false(asc.has_all_tags([STUNNED, BURNING] as Array[StringName]))
#endregion


#region has_any_tags
func test_an_empty_alternative_set_matches_nothing() -> void:
	asc.add_tag(STUNNED)
	var nothing: Array[StringName] = []
	# The mirror of has_all: an empty set contains nothing, so nothing matches.
	assert_false(asc.has_any_tags(nothing), "no alternatives means nothing to match")


func test_any_matches_when_one_is_present() -> void:
	asc.add_tag(BURNING)
	assert_true(asc.has_any_tags([STUNNED, BURNING] as Array[StringName]))
#endregion


#region Exact versus hierarchical
func test_exact_matches_only_itself() -> void:
	asc.add_tag(STUNNED)
	assert_true(asc.has_tag_exact(STUNNED), "the tag itself")
	assert_false(asc.has_tag_exact(STATUS), "not its parent")


func test_hierarchical_matches_a_child() -> void:
	asc.add_tag(STUNNED)
	assert_true(asc.has_tag(STATUS), "Status is answered by Status.Stunned")


func test_hierarchical_matches_the_tag_itself() -> void:
	asc.add_tag(STUNNED)
	assert_true(asc.has_tag(STUNNED))


func test_a_deeper_query_is_not_answered_by_its_ancestor() -> void:
	asc.add_tag(STATUS)
	# Direction matters. Holding `Status` does not mean holding `Status.Stunned`.
	assert_false(asc.has_tag(STUNNED), "an ancestor does not stand in for a child")


func test_a_prefix_without_a_separator_does_not_match() -> void:
	asc.add_tag(DAMAGE_FIRESTORM)
	# The separator is part of the rule. A bare begins_with gets this wrong, and
	# a fire resistance would silently apply to firestorms.
	assert_false(asc.has_tag(DAMAGE_FIRE), "Damage.Firestorm is not under Damage.Fire")


func test_a_short_tag_is_not_a_prefix_of_a_longer_word() -> void:
	asc.add_tag(&"AB")
	assert_false(asc.has_tag(&"A"), "AB is not under A")
#endregion


#region Reference counting
func test_a_tag_applied_twice_survives_one_removal() -> void:
	asc.add_tag(STUNNED)
	asc.add_tag(STUNNED)
	asc.remove_tag(STUNNED)
	# Two effects granted it; one ended. The other still wants it.
	assert_true(asc.has_tag_exact(STUNNED), "still held by the second grant")

	asc.remove_tag(STUNNED)
	assert_false(asc.has_tag_exact(STUNNED), "gone once both grants end")


func test_clearing_drops_a_tag_whatever_its_count() -> void:
	asc.add_tag(STUNNED)
	asc.add_tag(STUNNED)
	asc.clear_tag(STUNNED)
	assert_false(asc.has_tag_exact(STUNNED), "a cleanse ignores the count")


func test_removing_an_absent_tag_is_harmless() -> void:
	watch_signals(asc)
	asc.remove_tag(STUNNED)
	assert_signal_not_emitted(asc, "tag_removed", "nothing to announce")
#endregion


#region How much longer a tag lasts
## A timed effect answers in seconds.
func test_a_timed_tag_reports_the_seconds_it_has_left() -> void:
	Factory.apply(asc, Factory.granting(Factory.duration([], 5.0), [STUNNED] as Array[StringName]))
	assert_almost_eq(asc.get_tag_duration_remaining(STUNNED), 5.0, 0.0001)

	asc.scheduler.advance_time(2.0)
	assert_almost_eq(asc.get_tag_duration_remaining(STUNNED), 3.0, 0.0001, "and it counts down")


func test_a_tag_nothing_grants_has_no_time_left() -> void:
	assert_almost_eq(asc.get_tag_duration_remaining(STUNNED), 0.0, 0.0001)


## A permanent tag lasts forever, and forever is not zero.
##
## time_remaining is only ever set for a DURATION effect, so an INFINITE one
## granting the tag left it at 0.0 and this reported that a cooldown with no end
## had already ended - the exact opposite of the truth, to the one caller the
## function exists for.
func test_a_permanent_tag_reports_that_it_never_ends() -> void:
	Factory.apply(asc, Factory.granting(Factory.infinite([]), [STUNNED] as Array[StringName]))
	assert_true(
		is_inf(asc.get_tag_duration_remaining(STUNNED)),
		"an infinite effect grants it, so there is no second at which it runs out"
	)


## The longest wins, and an endless one is longer than any number.
func test_the_longest_grant_is_the_one_reported() -> void:
	Factory.apply(asc, Factory.granting(Factory.duration([], 2.0), [STUNNED] as Array[StringName]))
	Factory.apply(asc, Factory.granting(Factory.duration([], 9.0), [STUNNED] as Array[StringName]))
	assert_almost_eq(asc.get_tag_duration_remaining(STUNNED), 9.0, 0.0001)

	Factory.apply(asc, Factory.granting(Factory.infinite([]), [STUNNED] as Array[StringName]))
	assert_true(is_inf(asc.get_tag_duration_remaining(STUNNED)), "endless outlasts nine seconds")


## Turns are not seconds, and answering one with the other is how a UI shows
## "0s" over an effect that has three turns to run.
func test_a_turn_based_tag_is_counted_in_turns_not_seconds() -> void:
	Factory.apply(
		asc, Factory.granting(Factory.turn_based([], 3), [STUNNED] as Array[StringName])
	)
	assert_eq(asc.get_tag_turns_remaining(STUNNED), 3, "three turns")
	assert_almost_eq(
		asc.get_tag_duration_remaining(STUNNED), 0.0, 0.0001,
		"and no seconds, because it does not run on a clock"
	)

	asc.advance_turn()
	assert_eq(asc.get_tag_turns_remaining(STUNNED), 2, "and it counts down in turns")


func test_a_timed_tag_has_no_turns() -> void:
	Factory.apply(asc, Factory.granting(Factory.duration([], 5.0), [STUNNED] as Array[StringName]))
	assert_eq(asc.get_tag_turns_remaining(STUNNED), 0)


## An inhibited effect is not granting anything.
##
## `granted_tags` stays populated while an effect is inhibited - it is the
## receipt of what the effect would grant, and that is what lets uninhibiting
## put the same tags back. It is not a statement that the owner holds them, and
## these two answered as if it were: `has_tag` said no while the very same call
## reported seconds, and forever, left on it.
func test_an_inhibited_effect_reports_no_time_left_on_a_tag_it_is_not_granting() -> void:
	var timed: GameplayEffect = Factory.with_ongoing_requirement(
		Factory.granting(Factory.duration([], 5.0), [STUNNED] as Array[StringName]),
		[BURNING] as Array[StringName]
	)
	var endless: GameplayEffect = Factory.with_ongoing_requirement(
		Factory.granting(Factory.infinite([]), [STUNNED] as Array[StringName]),
		[BURNING] as Array[StringName]
	)
	var turned: GameplayEffect = Factory.with_ongoing_requirement(
		Factory.granting(Factory.turn_based([], 3), [STUNNED] as Array[StringName]),
		[BURNING] as Array[StringName]
	)

	asc.add_tag(BURNING)
	Factory.apply(asc, timed)
	Factory.apply(asc, endless)
	Factory.apply(asc, turned)
	assert_true(asc.has_tag(STUNNED), "all three are granting it while uninhibited")

	asc.remove_tag(BURNING)
	assert_false(asc.has_tag(STUNNED), "and none of them is, once inhibited")
	assert_almost_eq(asc.get_tag_duration_remaining(STUNNED), 0.0, 0.0001)
	assert_eq(asc.get_tag_turns_remaining(STUNNED), 0)


## Only the inhibited grants drop out, not the tag itself.
func test_an_uninhibited_grant_still_counts_beside_an_inhibited_one() -> void:
	var inhibited: GameplayEffect = Factory.with_ongoing_requirement(
		Factory.granting(Factory.infinite([]), [STUNNED] as Array[StringName]),
		[BURNING] as Array[StringName]
	)
	Factory.apply(asc, inhibited)
	Factory.apply(asc, Factory.granting(Factory.duration([], 4.0), [STUNNED] as Array[StringName]))

	assert_almost_eq(
		asc.get_tag_duration_remaining(STUNNED), 4.0, 0.0001,
		"the endless grant is inhibited, so four seconds is the whole answer"
	)
#endregion


#region Signals
func test_the_first_grant_announces_the_tag() -> void:
	watch_signals(asc)
	asc.add_tag(STUNNED)
	assert_signal_emitted(asc, "tag_added")
	assert_signal_emitted_with_parameters(asc, "tag_count_changed", [STUNNED, 1])


func test_a_second_grant_announces_only_the_count() -> void:
	asc.add_tag(STUNNED)
	watch_signals(asc)
	asc.add_tag(STUNNED)
	assert_signal_not_emitted(asc, "tag_added", "it was already present")
	assert_signal_emitted_with_parameters(asc, "tag_count_changed", [STUNNED, 2])
#endregion
