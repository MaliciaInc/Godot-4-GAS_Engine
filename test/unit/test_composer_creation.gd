## Making a call from the menu, and joining it to whatever the drag came out of.
##
## One thing a person did is one change to the file and one step to undo. So the
## test that carries the weight is the count: the statement and the cable have to
## arrive together, because a version that inserted the call and then connected
## it would leave a half-made node on screen whenever the second half failed.
##
## The other half is placement, and it is the same rule stated twice: a value is
## written before it is read. Dragged out of a value, the new call goes after the
## one producing it. Dragged out of an argument, it goes before the one that
## needs it - a local declared below the line that names it is a file that parses
## and does not compile.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"

var _routes: ComposerWiringRoutes = null
var _document: ComposerDocument = null


func before_each() -> void:
	_routes = ComposerWiringRoutes.new()
	_document = ComposerDocument.new()
	_routes.bind(_document)
	watch_signals(_routes)


#region Getting there
func _open(statements: Array) -> void:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	_document.open(HEAD + body, PATH)


func _node(written: String) -> ComposerNode:
	for node: ComposerNode in ComposerProjection.statements(_document.graph()):
		if node.text.contains(written):
			return node
	return null


func _context(
	mode: ComposerActionMenu.Context.Mode,
	node_id: StringName,
	port_id: StringName,
	type_name: StringName
) -> ComposerActionMenu.Context:
	var made: ComposerActionMenu.Context = ComposerActionMenu.Context.new()
	made.mode = mode
	made.node_id = node_id
	made.port_id = port_id
	made.kind = ComposerNode.PortKind.DATA
	made.type_name = type_name
	return made


## The first catalog entry the menu would offer for that drag.
##
## Asked of the menu rather than restated here, so a test cannot exercise a
## creation the menu would never have offered in the first place.
func _first_offered(
	mode: ComposerActionMenu.Context.Mode, type_name: StringName
) -> ComposerCatalog.Entry:
	var offered: Array[ComposerCatalog.Entry] = ComposerActionMenu.compatible_entries(
		_context(mode, &"", &"", type_name)
	)
	return offered[0] if not offered.is_empty() else null


func _taking(type_name: StringName) -> ComposerCatalog.Entry:
	return _first_offered(ComposerActionMenu.Context.Mode.FROM_PIN, type_name)


func _handing_back(type_name: StringName) -> ComposerCatalog.Entry:
	return _first_offered(ComposerActionMenu.Context.Mode.TO_PIN, type_name)


func _line_of(written: String) -> int:
	var lines: PackedStringArray = _document.printed().split("\n")
	for number: int in lines.size():
		if lines[number].contains(written):
			return number
	return -1
#endregion


#region Out of a value
## The new call goes after the one producing the value, and takes it.
func test_creating_from_a_value_puts_the_call_after_it_and_joins_them() -> void:
	_open([
		"var caster: AbilitySystemComponent = owner_asc",
		"return true",
	])
	var producer: ComposerNode = _node("var caster")
	var entry: ComposerCatalog.Entry = _taking(&"AbilitySystemComponent")
	assert_not_null(entry, "the engine takes one somewhere")

	var done: bool = _routes.create_and_connect(
		entry,
		_context(
			ComposerActionMenu.Context.Mode.FROM_PIN,
			producer.id,
			ComposerReader.VALUE_OUT,
			&"AbilitySystemComponent"
		)
	)

	assert_true(done, "it was made")
	assert_eq(_document.history().depth(), 1, "as one step")
	assert_gt(
		_line_of(String(entry.type_id)),
		_line_of("var caster"),
		"the call is written after the value it takes"
	)
	assert_eq(
		_document.graph().data_connections().size(), 1, "and the cable is there"
	)
#endregion


#region Out of an argument
## The new call goes before the one that needs it, keeping its result in a local.
func test_creating_from_an_argument_puts_the_local_above_the_consumer() -> void:
	_open(["apply_gameplay_effect(burning, null, 1.0)"])
	var consumer: ComposerNode = _node("apply_gameplay_effect")
	var entry: ComposerCatalog.Entry = _handing_back(&"float")
	assert_not_null(entry, "the engine hands one back somewhere")

	var done: bool = _routes.create_and_connect(
		entry,
		_context(
			ComposerActionMenu.Context.Mode.TO_PIN,
			consumer.id,
			StringName(ComposerReader.ARGUMENT % 2),
			&"float"
		)
	)

	assert_true(done, "it was made")
	assert_eq(_document.history().depth(), 1, "as one step")
	assert_lt(
		_line_of("var "),
		_line_of("apply_gameplay_effect"),
		"the local is declared above the line that names it"
	)
	assert_eq(
		_document.graph().data_connections().size(), 1, "and the cable is there"
	)


## The file still reads back, which is what makes the cable real.
func test_what_creation_writes_reads_back_as_the_graph_it_claims() -> void:
	_open(["apply_gameplay_effect(burning, null, 1.0)"])
	var consumer: ComposerNode = _node("apply_gameplay_effect")

	_routes.create_and_connect(
		_handing_back(&"float"),
		_context(
			ComposerActionMenu.Context.Mode.TO_PIN,
			consumer.id,
			StringName(ComposerReader.ARGUMENT % 2),
			&"float"
		)
	)

	assert_true(_document.graph().is_editable(), _document.graph().blocked_reason())
	var wire: ComposerGraph.Connection = _document.graph().data_connections()[0]
	assert_eq(
		wire.to_port,
		StringName(ComposerReader.ARGUMENT % 2),
		"the cable lands on the argument it was dragged from"
	)
#endregion


#region Plain, and refused
## Opened from the background, the call goes in before the ability ends.
##
## Everything after the return is unreachable, and a call written there is one
## somebody has to notice never ran.
func test_a_call_made_from_nothing_goes_in_before_the_end() -> void:
	_open(["commit_ability()", "return true"])
	var entry: ComposerCatalog.Entry = _taking(&"AbilitySystemComponent")
	assert_not_null(entry, "there is a call to make")

	var done: bool = _routes.create_and_connect(
		entry, ComposerActionMenu.Context.new()
	)

	assert_true(done, "it was made")
	assert_eq(_document.history().depth(), 1, "as one step")
	assert_true(_document.graph().is_editable(), _document.graph().blocked_reason())
	assert_lt(
		_line_of(String(entry.type_id)),
		_line_of("return true"),
		"written before the ability ends, where it can still run"
	)


## Nothing to make is refused, and nothing is written.
func test_a_call_that_is_not_there_is_refused() -> void:
	_open(["return true"])
	var before: String = _document.printed()

	var done: bool = _routes.create_and_connect(null, ComposerActionMenu.Context.new())

	assert_false(done, "there is no such call")
	assert_signal_emitted(_routes, "refused")
	assert_eq(_document.printed(), before, "and nothing was written")
	assert_eq(_document.history().depth(), 0, "with nothing to undo")
#endregion


#region Into an ability that has nothing in it yet
## The first call somebody adds to a new ability runs.
##
## New Ability writes a body whose only statement is `return true`, and the very
## next thing anybody does is add a call to it. Written after the return, the
## call is unreachable: the graph draws Entry straight to End with the new card
## hanging off nothing, and the ability does exactly what it did before.
func test_the_first_call_added_to_a_new_ability_runs_before_the_return() -> void:
	_document.open(ComposerAbilityTemplate.SOURCE, PATH)
	var entry: ComposerCatalog.Entry = _first_plain_call()
	assert_not_null(entry, "there is a call to add")

	assert_true(
		_routes.create_and_connect(entry, ComposerActionMenu.Context.new()),
		"the call was added"
	)

	var call_at: int = _line_of(String(entry.type_id))
	var return_at: int = _line_of("return true")
	assert_gt(call_at, -1, "the call is in the file")
	assert_gt(return_at, -1, "and so is the return")
	assert_lt(call_at, return_at, "with the call above it, where it runs")


## And the graph says so: execution reaches it, and goes on to the End.
func test_the_first_call_added_to_a_new_ability_is_wired_into_the_flow() -> void:
	_document.open(ComposerAbilityTemplate.SOURCE, PATH)
	assert_true(
		_routes.create_and_connect(_first_plain_call(), ComposerActionMenu.Context.new()),
		"the call was added"
	)

	var made: ComposerNode = _made_call()
	assert_not_null(made, "the call is drawn")
	assert_eq(
		ComposerFlow.predecessor_of(_document.graph(), made.id).id,
		ComposerFlow.ENTRY_ID,
		"Entry runs into it"
	)
	assert_eq(
		ComposerFlow.predecessor_of(
			_document.graph(), ComposerFlow.main_end(_document.graph()).id
		).id,
		made.id,
		"and it runs into the End"
	)


## A call that takes no arguments and hands nothing back, so adding it to an
## empty ability is only about where it lands.
func _first_plain_call() -> ComposerCatalog.Entry:
	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		if entry.parameters.is_empty() and not entry.awaits:
			return entry
	return null


func _made_call() -> ComposerNode:
	for node: ComposerNode in ComposerProjection.statements(_document.graph()):
		return node
	return null

#endregion
