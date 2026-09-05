## Breaking one exact cable, from the menu the pin offers.
##
## The Composer could only ever break every cable on a pin, which on a value
## feeding four statements is three cables somebody did not ask to lose. There is
## no hit-testing of curves behind this: the menu was opened on a known pin and
## the graph knows what touches it, which is enough to name each cable by what it
## reaches and to hand back the exact one that was picked.
##
## The gate is a fanout of two. Break one leaves one; break all leaves none; each
## is one entry in the history; and both can be taken back.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PRODUCER: String = "var caster"
const FIRST: String = "apply_gameplay_effect"
const SECOND: String = "apply_effect_to_target_data"

## One value feeding two statements: the smallest ability where breaking one
## cable and breaking all of them are different answers.
const FANOUT: Array = [
	"var caster: AbilitySystemComponent = owner_asc",
	"apply_gameplay_effect(burning, caster, 1.0)",
	"apply_effect_to_target_data(burning, caster)",
	"return true",
]

var _menu: ComposerPinMenu = null


func before_each() -> void:
	_menu = ComposerPinMenu.new()
	add_child_autofree(_menu)


#region Getting there
func _session() -> ComposerEditingSession:
	return ComposerEditingSession.opened(FANOUT)


## The statement every cable in the fixture leaves from.
func _from(session: ComposerEditingSession) -> StringName:
	return session.node(PRODUCER).id


## What the menu is offering, item by item, separators and all.
func _offered() -> PackedStringArray:
	var said: PackedStringArray = PackedStringArray()
	for index: int in _menu.item_count:
		said.append("---" if _menu.is_item_separator(index) else _menu.get_item_text(index))
	return said
#endregion


#region What it offers
## One entry per cable, named for what it reaches, then Break All.
func test_the_menu_names_every_cable_on_the_pin() -> void:
	var session: ComposerEditingSession = _session()
	var from: StringName = _from(session)

	_menu.open_for(session.document.graph(), from, ComposerReader.VALUE_OUT, Vector2.ZERO)

	var offered: PackedStringArray = _offered()
	assert_eq(offered.size(), 4, "two cables, a separator and Break All: %s" % [offered])
	assert_true(offered[0].contains("Apply Gameplay Effect"), "the first: %s" % [offered])
	assert_true(offered[1].contains("Apply Effect To Target Data"), "the second")
	assert_eq(offered[2], "---", "then a separator")
	assert_eq(offered[3], ComposerPinMenu.BREAK_ALL, "and the one that takes them all")


## In the order the statements they reach are written, not whatever order the
## graph happens to hold them in.
func test_the_cables_are_offered_in_the_order_they_are_written() -> void:
	var session: ComposerEditingSession = ComposerEditingSession.opened([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_effect_to_target_data(burning, caster)",
		"apply_gameplay_effect(burning, caster, 1.0)",
		"return true",
	])
	var from: StringName = _from(session)

	_menu.open_for(session.document.graph(), from, ComposerReader.VALUE_OUT, Vector2.ZERO)

	var offered: PackedStringArray = _offered()
	assert_true(
		offered[0].contains("Apply Effect To Target Data"),
		"the statement written first is offered first: %s" % [offered]
	)


## A pin with nothing on it says so, rather than opening empty.
func test_a_pin_with_nothing_on_it_says_so() -> void:
	var session: ComposerEditingSession = _session()

	_menu.open_for(
		session.document.graph(),
		session.node(FIRST).id,
		StringName(ComposerReader.ARGUMENT % 0),
		Vector2.ZERO
	)

	var offered: PackedStringArray = _offered()
	assert_eq(offered[0], ComposerPinMenu.NOTHING_ON_IT, "it says so: %s" % [offered])
	assert_true(_menu.is_item_disabled(0), "and there is nothing to press")
#endregion


#region What it asks for
## Picking a cable asks for that exact cable and no other.
func test_picking_a_cable_asks_for_that_one() -> void:
	var session: ComposerEditingSession = _session()
	var from: StringName = _from(session)
	_menu.open_for(session.document.graph(), from, ComposerReader.VALUE_OUT, Vector2.ZERO)
	watch_signals(_menu)

	_menu.id_pressed.emit(1)

	assert_signal_emitted(_menu, "break_link_requested")
	var asked: Array = get_signal_parameters(_menu, "break_link_requested")
	var edge: ComposerGraph.Connection = asked[0]
	assert_eq(edge.from_node, session.node(PRODUCER).id, "it leaves the value")
	assert_eq(edge.to_node, session.node(SECOND).id, "and lands on the second consumer")


## Picking Break All asks about the pin rather than about a cable.
func test_picking_break_all_asks_about_the_pin() -> void:
	var session: ComposerEditingSession = _session()
	var from: StringName = _from(session)
	_menu.open_for(session.document.graph(), from, ComposerReader.VALUE_OUT, Vector2.ZERO)
	watch_signals(_menu)

	_menu.id_pressed.emit(3)

	assert_signal_emitted(_menu, "break_all_requested")
	assert_signal_not_emitted(_menu, "break_link_requested", "and not about one cable")
#endregion


#region The gate: two cables, two answers
## Break one leaves one, break all leaves none, and each is one step back.
const BREAKING: Array = [
	["breaking one of them", true, 1, "apply_gameplay_effect(burning, null, 1.0)"],
	["breaking all of them", false, 0, "apply_gameplay_effect(burning, null, 1.0)"],
]


func test_what_each_break_leaves_behind() -> void:
	var checked: int = 0
	for row: Array in BREAKING:
		var described: String = row[0]
		var one: bool = row[1]
		var left: int = row[2]
		var written: String = row[3]

		var session: ComposerEditingSession = _session()
		var routes: ComposerWiringRoutes = ComposerWiringRoutes.new()
		routes.bind(session.document)
		var from: StringName = _from(session)
		var before: String = session.printed()
		_menu.open_for(session.document.graph(), from, ComposerReader.VALUE_OUT, Vector2.ZERO)
		_menu.break_link_requested.connect(routes.disconnect_edge)
		_menu.break_all_requested.connect(routes.break_pin)

		_menu.id_pressed.emit(0 if one else 3)

		assert_eq(session.cables(), left, "%s: cables left: %s" % [described, session.printed()])
		assert_true(
			session.printed().contains(written), "%s: and the file says so" % described
		)
		assert_eq(session.depth(), 1, "%s: as one step" % described)

		session.document.undo()
		assert_eq(session.printed(), before, "%s: which puts the file back" % described)

		_menu.break_link_requested.disconnect(routes.disconnect_edge)
		_menu.break_all_requested.disconnect(routes.break_pin)
		checked += 1
	assert_eq(checked, BREAKING.size(), "both answers were asked for")
#endregion
