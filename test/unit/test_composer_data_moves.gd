## Taking a cable off one pin and putting it on another.
##
## Two gestures wear the same clothes and are not the same edit. Dragging from a
## value's output onto another value's output re-points every consumer at the new
## producer - which already worked, and is covered where the rest of the fanout
## behaviour is. Dragging from one argument onto another moves a single value
## between slots, and that did nothing at all before this phase: the drag was
## reported, the controller read the destination pin's own label as if it were a
## producer, and what came out was an argument holding the word the card prints
## beside it.
##
## The other half is that a structural value takes a cable like any other. A
## branch's condition and what an end hands back are values, and until this phase
## nothing could be plugged into either.
##
## Everything here reads the file back afterwards. A move that only rearranged
## the graph would pass any test that asked the graph.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const CONSUMER: String = "apply_gameplay_effect"
const OTHER: String = "apply_effect_to_target_data"

## What `apply_gameplay_effect` declares for the argument a cable lands in.
const NO_CASTER: String = "null"


func _open(statements: Array) -> ComposerEditingSession:
	var session: ComposerEditingSession = ComposerEditingSession.opened(statements)
	watch_signals(session.controller)
	return session


## The pin standing for one value of one statement.
func _pin(session: ComposerEditingSession, said: String, slot: int) -> ComposerNode.Port:
	return session.node(said).pin_for_field(slot)


## Ctrl-drag: every cable on one pin goes to another pin.
func _move(
	session: ComposerEditingSession, from: String, from_slot: int, to: String, to_slot: int
) -> bool:
	return session.controller.move_connections(
		session.node(from).id,
		_pin(session, from, from_slot).id,
		session.node(to).id,
		_pin(session, to, to_slot).id
	)


#region A value moves from one slot to another
## Both ends of the move are written: this is GAS-010.
##
## The value arrives where it was dropped, and the slot it left goes back to
## what it would have been created holding - a data input takes one cable and
## cannot be left empty, because the argument text *is* the cable. The rows are
## the two states a destination can be in, and arriving on an occupied one
## replaces what was there rather than joining it: one input, one cable.
const CARRIED: Array = [
	[
		"onto an empty slot",
		[
			"var caster: AbilitySystemComponent = owner_asc",
			"apply_gameplay_effect(burning, caster, 1.0)",
			"apply_effect_to_target_data(burning, null)",
			"return true",
		],
		"apply_effect_to_target_data(burning, caster)",
		"apply_gameplay_effect(burning, null, 1.0)",
	],
	[
		"onto a slot that already had one",
		[
			"var first: AbilitySystemComponent = owner_asc",
			"var second: AbilitySystemComponent = other_asc",
			"apply_gameplay_effect(burning, first, 1.0)",
			"apply_effect_to_target_data(burning, second)",
			"return true",
		],
		"apply_effect_to_target_data(burning, first)",
		"apply_gameplay_effect(burning, null, 1.0)",
	],
]


func test_moving_a_value_between_slots_writes_both_ends() -> void:
	var checked: int = 0
	for row: Array in CARRIED:
		var described: String = row[0]
		var body: Array = row[1]
		var arrives: String = row[2]
		var leaves: String = row[3]

		var session: ComposerEditingSession = _open(body)
		var done: bool = _move(session, CONSUMER, 1, OTHER, 1)

		assert_true(done, "%s: the drag was taken" % described)
		assert_eq(session.line(OTHER), arrives, "%s: it arrived" % described)
		assert_eq(session.line(CONSUMER), leaves, "%s: and the slot it left is valid" % described)
		assert_eq(session.depth(), 1, "%s: as one step" % described)
		assert_eq(session.cables(), 1, "%s: with one cable, on the other card" % described)
		checked += 1
	assert_eq(checked, CARRIED.size(), "both destinations were tried")
#endregion


#region A move that cannot happen
## Nothing is written, whichever way the move is impossible.
##
## Both halves of that matter: an input move is two field changes, and a refusal
## that had already written the first would leave the origin unplugged from a
## value that never arrived anywhere. The rows are the three ways it does not
## happen - nothing to carry, a slot that will not take the type, and a value
## declared below where it would be named. Only the first is not a refusal:
## there was nothing to refuse.
const IMPOSSIBLE: Array = [
	[
		"there is no cable to move",
		[
			"apply_gameplay_effect(burning, null, 1.0)",
			"apply_effect_to_target_data(burning, null)",
			"return true",
		],
		CONSUMER, 1, OTHER, 1,
		true,
	],
	[
		"the slot will not take that type",
		[
			"var caster: AbilitySystemComponent = owner_asc",
			"apply_gameplay_effect(burning, caster, 1.0)",
			"return true",
		],
		CONSUMER, 1, CONSUMER, 2,
		false,
	],
	[
		"the value is declared below where it would land",
		[
			"apply_effect_to_target_data(burning, null)",
			"var caster: AbilitySystemComponent = owner_asc",
			"apply_gameplay_effect(burning, caster, 1.0)",
			"return true",
		],
		CONSUMER, 1, OTHER, 1,
		false,
	],
]


func test_a_move_that_cannot_happen_writes_nothing() -> void:
	var checked: int = 0
	for row: Array in IMPOSSIBLE:
		var described: String = row[0]
		var body: Array = row[1]
		var from: String = row[2]
		var from_slot: int = row[3]
		var to: String = row[4]
		var to_slot: int = row[5]
		var taken: bool = row[6]

		var session: ComposerEditingSession = _open(body)
		var before: String = session.printed()

		var done: bool = _move(session, from, from_slot, to, to_slot)

		assert_eq(done, taken, "%s: what the controller answered" % described)
		if not taken:
			assert_signal_emitted(session.controller, "refused")
		assert_eq(session.printed(), before, "%s: the file is untouched" % described)
		assert_eq(session.depth(), 0, "%s: with nothing to undo" % described)
		checked += 1
	assert_eq(checked, IMPOSSIBLE.size(), "every way of not happening was tried")
#endregion


#region A structural value takes a cable like any other
## Plugging and unplugging a condition, and what an end hands back.
##
## Unplugging leaves the declared default rather than the empty string or the
## name that was there: `if :` does not parse, and leaving the name behind would
## be a cable a person unplugged that is still drawn.
const STRUCTURAL: Array = [
	[
		"a local is plugged into a condition",
		["var ready: bool = can_activate()", "if false:", "\tcommit_ability()", "return true"],
		"var ready", "if ", 0, true,
		"if ready:", 1,
	],
	[
		"and unplugged from it again",
		["var ready: bool = can_activate()", "if ready:", "\tcommit_ability()", "return true"],
		"var ready", "if ", 0, false,
		"if false:", 0,
	],
	[
		"a local is handed back by the end",
		["var made: bool = commit_ability()", "return true"],
		"var made", "return", 0, true,
		"return made", 1,
	],
]


func test_a_structural_value_takes_a_cable_like_any_other() -> void:
	var checked: int = 0
	for row: Array in STRUCTURAL:
		var described: String = row[0]
		var body: Array = row[1]
		var producer: String = row[2]
		var said: String = row[3]
		var slot: int = row[4]
		var plugging: bool = row[5]
		var written: String = row[6]
		var cables: int = row[7]

		var session: ComposerEditingSession = _open(body)
		var edge: ComposerGraph.Connection = session.value_into(producer, said, slot)
		var done: bool = (
			session.controller.connect_edge(edge) if plugging
			else session.controller.disconnect_edge(edge)
		)

		assert_true(done, "%s: it was taken: %s" % [described, session.printed()])
		assert_eq(session.line(said), written, "%s: and the file says so" % described)
		assert_eq(session.cables(), cables, "%s: cables afterwards" % described)
		assert_eq(session.depth(), 1, "%s: in one step" % described)
		checked += 1
	assert_eq(checked, STRUCTURAL.size(), "every structural value was tried")
#endregion
