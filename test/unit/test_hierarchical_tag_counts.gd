## Counting a tag, and counting everything under it.
##
## A reference count answers "how many effects are granting this exact tag",
## which is the right question when one of them ends and the tag has to survive.
## It is the wrong question for anything watching a family of tags: a character
## with `State.Stunned` and `State.Rooted` is held by two different things, and
## losing the stun does not mean they can move.
##
## So there are two counts, and a listener on `State` hears about both of its
## children. What it must not hear is "it is held now" twice for one condition -
## the count going one to two is a second thing arriving, not the state
## starting - so presence is announced only where the count crossed zero.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")

const STATE: StringName = &"State"
const STUNNED: StringName = &"State.Stunned"
const ROOTED: StringName = &"State.Rooted"
const DEEP: StringName = &"State.Debuff.Silenced"
const DEBUFF: StringName = &"State.Debuff"
const STATELY: StringName = &"Stately"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var tags: GameplayTagRuntime = null

## Every parent-aware announcement, in order, as [tag, count] and [tag, present].
var counts: Array = []
var presence: Array = []


func before_each() -> void:
	fixture = Fixture.create("Tagged")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	tags = asc.tags
	counts = []
	presence = []
	asc.tag_or_child_count_changed.connect(_record_count)
	asc.tag_or_child_presence_changed.connect(_record_presence)


func after_each() -> void:
	fixture = null
	asc = null
	tags = null


func _record_count(tag: StringName, new_count: int) -> void:
	counts.append([tag, new_count])


func _record_presence(tag: StringName, present: bool) -> void:
	presence.append([tag, present])


#region Two counts, because they are two questions
## Both counts of one arrangement, side by side.
##
## One table because they are two answers to the same state and the point is
## where they differ: on a leaf they agree, and a caller wired to the wrong one
## looks right until something has children.
##
##     [what is being asked, the tag, the exact count, the family count]
func _both_counts() -> Array:
	return [
		["a tag granted twice", STUNNED, 2, 2],
		["a tag granted once", ROOTED, 1, 1],
		["a parent nothing holds directly", STATE, 0, 3],
		["a tag nobody holds at all", &"Nothing", 0, 0],
	]


func test_the_exact_count_is_the_tag_and_the_family_count_is_all_of_it() -> void:
	asc.add_tag(STUNNED)
	asc.add_tag(STUNNED)
	asc.add_tag(ROOTED)

	var rows: Array = _both_counts()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var tag: StringName = row[1]
		var alone: int = row[2]
		var family: int = row[3]

		assert_eq(tags.count_exact(tag), alone, "%s: held this many times itself" % described)
		assert_eq(tags.count(tag), family, "%s: and this many with everything under it" % described)
		checked += 1
	assert_eq(checked, rows.size(), "every tag was asked about")


## A prefix that does not end at a separator is a different tag, and counts
## as one. `Stately` is not under `State`, the way `AB` is not under `A`.
func test_a_prefix_is_not_a_parent() -> void:
	asc.add_tag(STATELY)

	assert_eq(tags.count(STATE), 0, "`Stately` is its own tag")
	assert_eq(tags.count(STATELY), 1, "and it is held")


## Every ancestor of a deep tag holds it, and nothing else does.
func test_a_deep_tag_is_held_by_every_ancestor() -> void:
	asc.add_tag(DEEP)

	assert_eq(tags.count(DEEP), 1, "itself")
	assert_eq(tags.count(DEBUFF), 1, "its parent")
	assert_eq(tags.count(STATE), 1, "and its grandparent")
	assert_eq(
		GameplayTagRuntime.ancestors_of(DEEP),
		[DEEP, DEBUFF, STATE] as Array[StringName],
		"nearest first, and nothing beyond the root"
	)
#endregion


#region What a listener on the parent hears
## The state machine the phase specifies, one step at a time.
##
## Written as one test rather than four because the point is the sequence: what
## the third step announces depends on what the first two left behind, and four
## tests each re-arranging the state would each be asserting a different thing
## than the one this is about.
func test_a_listener_on_the_parent_hears_the_family_change() -> void:
	asc.add_tag(STUNNED)
	assert_eq(counts, [[STUNNED, 1], [STATE, 1]], "stunned: the tag, then its parent")
	assert_eq(presence, [[STUNNED, true], [STATE, true]], "and both arrived")

	counts = []
	presence = []
	asc.add_tag(ROOTED)
	assert_eq(counts, [[ROOTED, 1], [STATE, 2]], "rooted: `State` is held twice")
	assert_eq(presence, [[ROOTED, true]], "`State` was already held, so it did not arrive again")

	counts = []
	presence = []
	asc.remove_tag(STUNNED)
	assert_eq(counts, [[STUNNED, 0], [STATE, 1]], "the stun went, the root remains")
	assert_eq(presence, [[STUNNED, false]], "`State` is still held, so it did not go away")

	counts = []
	presence = []
	asc.remove_tag(ROOTED)
	assert_eq(counts, [[ROOTED, 0], [STATE, 0]], "and now nothing holds it")
	assert_eq(presence, [[ROOTED, false], [STATE, false]], "so the family went away too")


## A count change that is not a state change announces neither arrival nor
## departure, in both directions.
##
##     [what happened, whether the second grant arrives or is given back,
##      what both counts read afterwards]
func _second_grants() -> Array:
	return [
		["a second grant of a tag already held", "add", 2],
		["one of two grants given back", "remove", 1],
	]


func test_a_count_change_that_is_not_a_state_change_announces_nothing() -> void:
	var rows: Array = _second_grants()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var which: String = row[1]
		var after: int = row[2]

		before_each()
		asc.add_tag(STUNNED)
		if which == "remove":
			asc.add_tag(STUNNED)
		counts = []
		presence = []

		if which == "add":
			asc.add_tag(STUNNED)
		else:
			asc.remove_tag(STUNNED)

		assert_eq(counts, [[STUNNED, after], [STATE, after]], "%s: both counts moved" % described)
		assert_eq(presence, [], "%s: and the character is stunned either way" % described)
		checked += 1
	assert_eq(checked, rows.size(), "both directions were offered")


## A cleanse takes the whole count at once, and that is a departure.
func test_clearing_a_tag_outright_is_a_departure() -> void:
	asc.add_tag(STUNNED)
	asc.add_tag(STUNNED)
	counts = []
	presence = []

	asc.clear_tag(STUNNED)

	assert_eq(counts, [[STUNNED, 0], [STATE, 0]], "however many grants there were")
	assert_eq(presence, [[STUNNED, false], [STATE, false]], "it is gone")


## Removing a tag nobody holds announces nothing at all.
func test_removing_a_tag_nobody_holds_announces_nothing() -> void:
	asc.remove_tag(STUNNED)

	assert_eq(counts, [], "no count changed")
	assert_eq(presence, [], "and nothing came or went")
#endregion


#region The exact signals still mean the exact tag
## `tag_count_changed` reports the reference count, not the family's.
##
## The two live side by side and a listener choosing one has to get the one it
## chose. The tag granted here has descendants already held, which is the only
## arrangement where the two counts of one tag differ - grant a leaf and both
## answers are the same number, and a signal wired to the wrong one looks right.
func test_the_exact_signal_still_reports_the_exact_count() -> void:
	asc.add_tag(DEEP)
	asc.add_tag(DEEP)
	var exact: Array = []
	asc.tag_count_changed.connect(func(tag: StringName, new_count: int) -> void:
		exact.append([tag, new_count])
	)
	counts = []

	asc.add_tag(DEBUFF)

	assert_eq(exact, [[DEBUFF, 1]], "one grant of it, whatever is underneath")
	assert_eq(counts, [[DEBUFF, 3], [STATE, 3]], "while the family count says three")
#endregion
