## What the catalog offers, and why it never offers what it will refuse.
##
## A menu that shows a choice it will not honour teaches people to distrust the
## menu, and they go back to typing GDScript. So the filter is the product: what
## is listed for a pin is exactly what could be joined to that pin.
##
## The search runs after the filter and never instead of it - typing narrows the
## list and cannot widen it, so nothing incompatible can be reached by spelling
## it.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const EFFECT: StringName = &"GameplayEffect"
## A type the engine really does hand back: `get_ability_level()` returns one.
const PRODUCED: StringName = &"float"


func _context(
	mode: ComposerActionMenu.Context.Mode,
	kind: ComposerNode.PortKind,
	type_name: StringName
) -> ComposerActionMenu.Context:
	var made: ComposerActionMenu.Context = ComposerActionMenu.Context.new()
	made.mode = mode
	made.kind = kind
	made.type_name = type_name
	return made


func _from_value(type_name: StringName) -> ComposerActionMenu.Context:
	return _context(
		ComposerActionMenu.Context.Mode.FROM_PIN, ComposerNode.PortKind.DATA, type_name
	)


func _into_argument(type_name: StringName) -> ComposerActionMenu.Context:
	return _context(
		ComposerActionMenu.Context.Mode.TO_PIN, ComposerNode.PortKind.DATA, type_name
	)


func _keys_of(entries: Array[ComposerCatalog.Entry]) -> Array[StringName]:
	var found: Array[StringName] = []
	for entry: ComposerCatalog.Entry in entries:
		found.append(entry.key)
	return found


#region Everything, and everything runnable
## Opened from nothing, the menu is the catalog.
func test_opened_from_nothing_it_offers_the_whole_catalog() -> void:
	var context: ComposerActionMenu.Context = ComposerActionMenu.Context.new()

	var offered: Array[ComposerCatalog.Entry] = ComposerActionMenu.compatible_entries(
		context
	)

	assert_eq(offered.size(), ComposerCatalog.all().size(), "all of it")


## A run of control fits every call, because every call is a statement.
func test_a_run_of_control_offers_every_call() -> void:
	var from_exec: ComposerActionMenu.Context = _context(
		ComposerActionMenu.Context.Mode.FROM_PIN,
		ComposerNode.PortKind.EXECUTION,
		&""
	)
	var into_exec: ComposerActionMenu.Context = _context(
		ComposerActionMenu.Context.Mode.TO_PIN, ComposerNode.PortKind.EXECUTION, &""
	)

	assert_eq(
		ComposerActionMenu.compatible_entries(from_exec).size(),
		ComposerCatalog.all().size(),
		"everything can run after something"
	)
	assert_eq(
		ComposerActionMenu.compatible_entries(into_exec).size(),
		ComposerCatalog.all().size(),
		"and before it"
	)


## Whatever the context, the same one always offers the same list in the same
## order - so the second thing down is the second thing down tomorrow.
func test_the_same_context_offers_the_same_list_in_the_same_order() -> void:
	var context: ComposerActionMenu.Context = _from_value(EFFECT)

	var once: Array[ComposerCatalog.Entry] = ComposerActionMenu.compatible_entries(context)
	var again: Array[ComposerCatalog.Entry] = ComposerActionMenu.compatible_entries(context)

	assert_gt(once.size(), 0, "there is something to order")
	for position: int in once.size():
		assert_eq(once[position].key, again[position].key, "entry %d" % position)
#endregion


#region Dragged out of a value
## Only calls that take that value are offered.
func test_dragging_a_value_offers_only_calls_that_take_one() -> void:
	var context: ComposerActionMenu.Context = _from_value(EFFECT)

	var offered: Array[ComposerCatalog.Entry] = ComposerActionMenu.compatible_entries(
		context
	)

	assert_gt(offered.size(), 0, "something takes an effect")
	assert_lt(offered.size(), ComposerCatalog.all().size(), "and not everything does")
	for entry: ComposerCatalog.Entry in offered:
		assert_gte(
			ComposerActionMenu.first_argument_for(context, entry),
			0,
			"%s has somewhere to put it" % entry.type_id
		)


## Nothing that cannot take it is listed.
##
## Checked against the whole catalog rather than against the offered list: the
## failure that matters is an entry wrongly *included*, and looking only at what
## was offered cannot see one wrongly left out either.
func test_nothing_that_cannot_take_the_value_is_listed() -> void:
	var context: ComposerActionMenu.Context = _from_value(EFFECT)
	var offered: Array[ComposerCatalog.Entry] = ComposerActionMenu.compatible_entries(
		context
	)
	var keys: Array[StringName] = _keys_of(offered)

	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		var fits: bool = ComposerActionMenu.first_argument_for(context, entry) >= 0
		assert_eq(keys.has(entry.key), fits, "%s" % entry.type_id)


## The argument a value goes into is the first that accepts it, every time.
##
## Both halves are asserted for every entry: the one chosen does accept the
## value, and none before it did. A test that only walked the arguments before
## the chosen one asserts nothing at all whenever the answer is nought - which,
## for most calls, it is.
func test_the_argument_chosen_is_the_first_that_accepts_it() -> void:
	var context: ComposerActionMenu.Context = _from_value(EFFECT)

	var checked: int = 0
	for entry: ComposerCatalog.Entry in ComposerActionMenu.compatible_entries(context):
		var chosen: int = ComposerActionMenu.first_argument_for(context, entry)
		assert_true(
			ComposerTypes.accepts(entry.parameters[chosen].type_name, context.type_name),
			"%s: argument %d takes it" % [entry.type_id, chosen]
		)
		for earlier: int in chosen:
			assert_false(
				ComposerTypes.accepts(
					entry.parameters[earlier].type_name, context.type_name
				),
				"%s: argument %d was passed over" % [entry.type_id, earlier]
			)
		checked += 1
	assert_gt(checked, 0, "entries were actually compared")


## A value whose place is not the first argument still lands where it belongs.
##
## The rule only does work when the answer is not nought, and for most calls it
## is: `apply_gameplay_effect` takes an effect first and the component second, so
## a component dragged onto it must skip an argument to get where it goes.
func test_a_value_that_belongs_further_along_skips_the_arguments_before_it() -> void:
	var context: ComposerActionMenu.Context = _from_value(&"AbilitySystemComponent")

	var furthest: int = 0
	for entry: ComposerCatalog.Entry in ComposerActionMenu.compatible_entries(context):
		furthest = maxi(furthest, ComposerActionMenu.first_argument_for(context, entry))

	assert_gt(furthest, 0, "at least one call takes it somewhere other than first")
#endregion


#region Dragged out of an argument
## Only calls that hand back something that argument could hold are offered.
func test_dragging_from_an_argument_offers_only_calls_that_hand_one_back() -> void:
	var context: ComposerActionMenu.Context = _into_argument(PRODUCED)

	var offered: Array[ComposerCatalog.Entry] = ComposerActionMenu.compatible_entries(
		context
	)

	assert_gt(offered.size(), 0, "something hands one back")
	for entry: ComposerCatalog.Entry in offered:
		assert_true(
			ComposerTypes.is_a_value(entry.result_type),
			"%s hands back something real, not Nil" % entry.type_id
		)
		assert_true(
			ComposerTypes.accepts(PRODUCED, entry.result_type),
			"%s hands back something that fits" % entry.type_id
		)


## A call that hands back nothing is never offered as a value.
##
## Reflection reports a void method as returning `Nil`, which is not empty and is
## treated as untyped - so `accepts()` says it fits everywhere. Asked the wrong
## way, every void call in the engine is offered as a way to fill an argument,
## and picking one writes `var x: Nil = end_ability()`.
func test_a_call_that_hands_back_nothing_is_never_offered_as_a_value() -> void:
	var wanted: Array[StringName] = [PRODUCED, EFFECT, &"float"]
	var voids: int = 0
	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		if ComposerTypes.is_a_value(entry.result_type):
			continue
		voids += 1
		for type_name: StringName in wanted:
			var keys: Array[StringName] = _keys_of(
				ComposerActionMenu.compatible_entries(_into_argument(type_name))
			)
			assert_false(keys.has(entry.key), "%s is not offered" % entry.type_id)
	assert_gt(voids, 0, "the engine does declare calls that hand back nothing")


## And the factory will not write a local for one either.
func test_no_local_is_written_for_a_call_that_hands_back_nothing() -> void:
	var written: int = 0
	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		if ComposerTypes.is_a_value(entry.result_type):
			continue
		assert_eq(
			ComposerStatementFactory.local_call(
				entry, "res://abilities/probe.gd", PackedStringArray()
			),
			"",
			"%s cannot be kept in a local" % entry.type_id
		)
		written += 1
	assert_gt(written, 0, "there were such calls to refuse")


## A call that suspends is not offered as a value.
##
## Its result is a task to wait on, not a value to pass, and offering one here
## would write `var x = await ...` into an argument as though the two were the
## same thing.
func test_a_call_that_suspends_is_not_offered_as_a_value() -> void:
	var offered: Array[ComposerCatalog.Entry] = ComposerActionMenu.compatible_entries(
		_into_argument(PRODUCED)
	)

	assert_gt(offered.size(), 0, "something hands one back")
	for entry: ComposerCatalog.Entry in offered:
		assert_false(entry.awaits, "%s does not suspend" % entry.type_id)


## And a call that suspends is offered for a run of control, where it belongs.
func test_a_call_that_suspends_is_still_offered_where_it_can_run() -> void:
	var suspending: int = 0
	var keys: Array[StringName] = _keys_of(
		ComposerActionMenu.compatible_entries(
			_context(
				ComposerActionMenu.Context.Mode.FROM_PIN,
				ComposerNode.PortKind.EXECUTION,
				&""
			)
		)
	)

	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		if not entry.awaits:
			continue
		suspending += 1
		assert_true(keys.has(entry.key), "%s can still be run" % entry.type_id)
	assert_gt(suspending, 0, "the engine does declare calls that suspend")
#endregion


#region Searching
## Typing narrows what was offered, and cannot reach past it.
func test_the_search_narrows_the_filtered_list_and_never_widens_it() -> void:
	var context: ComposerActionMenu.Context = _from_value(EFFECT)
	var offered: Array[ComposerCatalog.Entry] = ComposerActionMenu.compatible_entries(
		context
	)
	var keys: Array[StringName] = _keys_of(offered)

	var found: Array[ComposerCatalog.Entry] = ComposerActionMenu.matching(offered, "a")

	assert_lte(found.size(), offered.size(), "no more than was offered")
	for entry: ComposerCatalog.Entry in found:
		assert_true(keys.has(entry.key), "%s was offered before it was typed" % entry.type_id)


## An empty search changes nothing.
func test_an_empty_search_leaves_the_list_alone() -> void:
	var offered: Array[ComposerCatalog.Entry] = ComposerActionMenu.compatible_entries(
		_from_value(EFFECT)
	)

	assert_eq(ComposerActionMenu.matching(offered, "   ").size(), offered.size())


## A search nothing matches finds nothing, rather than falling back to all.
func test_a_search_nothing_matches_finds_nothing() -> void:
	var offered: Array[ComposerCatalog.Entry] = ComposerActionMenu.compatible_entries(
		_from_value(EFFECT)
	)

	assert_eq(ComposerActionMenu.matching(offered, "zzzzzz").size(), 0)
#endregion
