## The boundary a rejection unwinds, and the two things F6.6.6 made reversible.
##
## A guess is rarely one thing. An ability that predicts spends, holds a tag,
## starts a playback and plays a spark, and every one of those was done because
## the one before it was - so what a refusal has to take back is the set, in the
## order it was written and no other. The window is that set: a game opens one,
## does its work, and closes it, rather than carrying the key through four call
## sites and forgetting it at the fifth.
##
## And two of those four are only reversible while they are still this
## machine's to reverse. A tag is a reference count the authority also
## replicates, so putting the old number back on top of a reading that arrived
## since would be overwriting the authority with arithmetic done locally. A
## playback belongs to one activation on one surface, and another ability that
## has taken the surface is playing something this guess has no business
## stopping. Both are asked, both answer no, and answering no is not a failure.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Bench = preload("res://test/fixtures/ability_task_bench.gd")

const OWNING_PEER: int = 2
const BURNING: StringName = &"State.Burning"
const MANA: StringName = &"mana"
const CAST: StringName = &"cast"
const OTHER: StringName = &"other"

var bench: PredictionBench = null
var journal: GameplayPredictionJournal = null
var asc: AbilitySystemComponent = null
var key: GameplayPredictionKey = null


func before_each() -> void:
	bench = PredictionBench.stand(self, OWNING_PEER, {MANA: 100.0})
	journal = bench.journal
	asc = bench.asc()
	key = bench.key


func after_each() -> void:
	bench.dispose()
	bench = null
	journal = null
	asc = null
	key = null


#region The boundary
## What happens inside a window belongs to the guess it was opened under.
##
## The whole reason for a window: a game that predicts four things does not
## have to name the guess four times, and the one it would have forgotten to
## name is the one a refusal would then leave behind.
func test_what_happens_inside_a_window_belongs_to_the_guess() -> void:
	assert_true(journal.open_window(key), "it opened")

	journal.record(GameplayPredictionOperation.cost(null, MANA, 30.0))
	journal.record(GameplayPredictionOperation.tag(null, BURNING, 0, 1))

	assert_eq(journal.under(key).size(), 2, "both belong to the guess")
	assert_true(journal.close_window(key), "and it closed")


## Nothing is recorded outside one, unless it names its own guess.
##
## An operation with no key and no window is a thing nobody can take back,
## which is worse than not writing it down: it would sit in the journal
## claiming to be owed and never be unwound by anything.
func test_nothing_is_recorded_outside_a_window_without_a_guess() -> void:
	journal.record(GameplayPredictionOperation.cost(null, MANA, 30.0))

	assert_eq(journal.size(), 0, "it was not written down")


## One that names its own guess keeps it.
##
## An operation deriving from a key inside somebody else's window is still that
## key's. Quietly re-parenting it would unwind it at the wrong time, which is
## the failure the window exists to prevent wearing the other face.
func test_an_operation_that_names_its_own_guess_keeps_it() -> void:
	var separate: GameplayPredictionKey = journal.next_key(OWNING_PEER)
	journal.open_window(key)

	journal.record(GameplayPredictionOperation.cost(separate, MANA, 10.0))

	assert_eq(journal.under(key).size(), 0, "the window did not take it")
	assert_eq(journal.under(separate).size(), 1, "and it is still its own")


## A second window nests inside the first rather than being refused.
##
## A guess predicted while an earlier one is still waiting on its own answer
## is a guess made because of that one - GAP-02 - and what follows while both
## are open belongs to the innermost, not to whichever opened first.
func test_a_second_window_nests_inside_the_first() -> void:
	assert_true(journal.open_window(key), "the outer opened")
	var inner: GameplayPredictionKey = journal.next_key_in_window(OWNING_PEER)
	assert_true(journal.open_window(inner), "and a second nests rather than being refused")

	journal.record(GameplayPredictionOperation.cost(null, MANA, 10.0))

	assert_eq(journal.under(key).size(), 1, "the outer stands on nothing else, but owns what stands on it")
	assert_eq(journal.under(inner).size(), 1, "and the operation itself is the inner's own")
	assert_true(journal.close_window(inner), "the inner closes")
	assert_eq(journal.current_window(), key, "and the outer is current again")
	assert_true(journal.close_window(key), "then the outer closes too")


## Windows answer in whichever order their own round trips finish in, not
## necessarily the order they opened in - and the inner is unaffected by the
## outer closing first.
func test_an_outer_window_can_close_before_the_inner_it_is_standing_under() -> void:
	journal.open_window(key)
	var inner: GameplayPredictionKey = journal.next_key_in_window(OWNING_PEER)
	journal.open_window(inner)

	assert_true(journal.close_window(key), "the outer's own answer arrived first")
	assert_eq(journal.current_window(), inner, "the inner is still open, and still current")
	journal.record(GameplayPredictionOperation.cost(null, MANA, 5.0))
	assert_eq(journal.under(inner).size(), 1, "and still where new work attributes")
	assert_true(journal.close_window(inner), "and it closes on its own answer, same as ever")


## A key that was never opened cannot close anything, whether or not
## something else is open.
func test_a_key_that_was_never_opened_cannot_close_anything() -> void:
	var stranger: GameplayPredictionKey = journal.next_key(OWNING_PEER)
	assert_true(journal.open_window(key), "the real one opened")

	assert_false(journal.close_window(stranger), "the stranger closes nothing")
	assert_eq(journal.current_window(), key, "and the real one is still open")
	assert_true(journal.close_window(key), "which closes on its own key, same as ever")


## Rejecting an outer guess reverses what a guess nested under it did too,
## even though the inner's own window is still open and its own answer has
## not arrived yet.
##
## This is the whole point of nesting one window inside another rather than
## refusing the second: what the inner did was only ever justified by the
## outer being right, and the outer turning out wrong takes it with it.
func test_rejecting_an_outer_guess_also_reverses_what_a_nested_one_did() -> void:
	journal.open_window(key)
	asc.set_attribute_base(MANA, 70.0)
	journal.record(GameplayPredictionOperation.cost(null, MANA, 30.0))

	var inner: GameplayPredictionKey = journal.next_key_in_window(OWNING_PEER)
	journal.open_window(inner)
	asc.set_attribute_base(MANA, 50.0)
	journal.record(GameplayPredictionOperation.cost(null, MANA, 20.0))

	assert_eq(journal.reject(key, asc), 2, "both the outer's own spend and the nested one's")
	assert_almost_eq(asc.get_attribute_base(MANA), 100.0, 0.001, "both refunded")
	assert_eq(journal.under(inner).size(), 0, "nothing is left owed under the inner either")


## A window closes itself when the guess it was open under is answered.
##
## Left open, it would go on attributing later work to a key nothing is waiting
## on, and the next rejection would unwind work that had nothing to do with it.
func test_a_window_closes_when_its_guess_is_answered() -> void:
	journal.open_window(key)
	journal.record(GameplayPredictionOperation.cost(null, MANA, 30.0))

	journal.reject(key, asc)
	journal.record(GameplayPredictionOperation.cost(null, MANA, 5.0))

	assert_eq(journal.size(), 0, "nothing was attributed to the settled guess")


## Everything in a window comes off newest first.
##
## The cooldown went on because the cost was paid; the tag was held because the
## cooldown started. Undoing them in the order they were written would take the
## ground out from under what was standing on it.
func test_a_window_comes_off_newest_first() -> void:
	journal.open_window(key)
	var first: GameplayPredictionOperation = GameplayPredictionOperation.cost(null, MANA, 30.0)
	var second: GameplayPredictionOperation = GameplayPredictionOperation.tag(
		null, BURNING, 0, 1
	)
	journal.record(first)
	journal.record(second)

	var owed: Array[GameplayPredictionOperation] = journal.under(key)

	assert_same(owed[0], second, "the last thing done is offered back first")
	assert_same(owed[1], first, "and the first is offered back last")


## A refusal arriving twice unwinds once.
##
## The duplicate is ordinary rather than exceptional - a resend, a reorder, a
## peer answering an answer - and the second one finding nothing left is what
## makes it harmless.
func test_a_refusal_arriving_twice_unwinds_once() -> void:
	journal.open_window(key)
	# The guess spent it, which is what makes putting it back visible: a
	# reversal against a bill nobody paid would read as a refund.
	asc.set_attribute_base(MANA, 70.0)
	journal.record(GameplayPredictionOperation.cost(null, MANA, 30.0))
	journal.close_window(key)

	assert_eq(journal.reject(key, asc), 1, "the first refusal put it back")
	assert_eq(journal.reject(key, asc), 0, "the second had nothing to put back")
	assert_almost_eq(asc.get_attribute_base(MANA), 100.0, 0.001, "and it was put back once")
#endregion


#region A tag held ahead of the answer
##     [what happened, held now, the guess was from, to, put back, left at]
func _tag_cases() -> Array:
	return [
		["a guess nothing has touched since", 3, 2, 3, 1, 2],
		["one the authority has moved since", 2, 0, 1, 0, 2],
		["one that moved no count at all", 1, 1, 1, 0, 1],
	]


## A tag goes back to the count it had, while that count is still ours.
##
## The count rather than one removal, because a tag is a reference count and a
## guess that took it from two to three is not undone by taking it to zero. And
## the count is also the ownership check, in the only form a tag has one: a
## reading that arrived after the guess has already written what the authority
## believes, and this machine putting its own arithmetic back on top would undo
## it with nothing to correct it until that tag next changed.
func test_a_tag_is_put_back_only_while_the_count_is_still_the_guess_s() -> void:
	var rows: Array = _tag_cases()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var held: int = row[1]
		var was: int = row[2]
		var now: int = row[3]
		var reversals: int = row[4]
		var left_at: int = row[5]

		before_each()
		for _index: int in held:
			asc.add_tag(BURNING)
		journal.record(GameplayPredictionOperation.tag(key, BURNING, was, now))

		assert_eq(journal.reject(key, asc), reversals, described)
		assert_eq(
			asc.tags.count_exact(BURNING), left_at, "%s: the count it is left at" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "every ending was offered")
#endregion


#region A playback started ahead of the answer
## A refused animation is stopped while this activation still owns the surface.
func test_a_refused_animation_is_stopped_while_it_is_still_ours() -> void:
	var bench: AbilityTaskBench = Bench.stand(self, &"Ability.Guessed")
	var player: AnimationPlayer = Bench.player(self, [CAST] as Array[StringName])
	var claim: GameplayAnimationOwnership = GameplayAnimationOwnership.claim(
		player, bench.ability, CAST
	)
	player.play(CAST)
	journal.record(GameplayPredictionOperation.animation(key, claim))

	assert_eq(journal.reject(key, asc), 1, "it was stopped")
	assert_false(player.is_playing(), "and the surface is quiet")
	assert_null(
		GameplayAnimationOwnership.holder_of(player), "with the claim given back"
	)


## And left alone once somebody else has taken the surface.
##
## Taking it over is a legitimate thing for a second ability to do. What this
## guess must not do is stop what that ability started - the player would go
## still in the middle of an animation nobody refused.
func test_an_animation_somebody_else_took_is_left_alone() -> void:
	var bench: AbilityTaskBench = Bench.stand(self, &"Ability.Guessed")
	var player: AnimationPlayer = Bench.player(self, [CAST, OTHER] as Array[StringName])
	var claim: GameplayAnimationOwnership = GameplayAnimationOwnership.claim(
		player, bench.ability, CAST
	)
	journal.record(GameplayPredictionOperation.animation(key, claim))
	# Somebody else reaches for the same surface and wins, which is allowed.
	GameplayAnimationOwnership.claim(player, bench.ability, OTHER)
	player.play(OTHER)

	assert_eq(journal.reject(key, asc), 0, "the guess stopped nothing")
	assert_true(player.is_playing(), "and what the other ability started is still going")


## A surface that no longer exists is not one anybody is waiting on.
func test_an_animation_whose_surface_is_gone_reverses_nothing() -> void:
	var bench: AbilityTaskBench = Bench.stand(self, &"Ability.Guessed")
	var player: AnimationPlayer = AnimationPlayer.new()
	var claim: GameplayAnimationOwnership = GameplayAnimationOwnership.claim(
		player, bench.ability, CAST
	)
	journal.record(GameplayPredictionOperation.animation(key, claim))
	player.free()

	assert_eq(journal.reject(key, asc), 0, "there was nothing left to stop")
#endregion
