## Picking a call from a drag that came out of an execution pin.
##
## Every one of these used to do the same thing: the statement was written just
## before the ability's `return`, whichever pin the drag started from, and the
## person was left to drag it into place afterwards - if they noticed. What is
## asked here is that the new statement runs where the drag said it should, on
## the path that asked for it and on no other.
##
## Two of the paths do not exist in the file until somebody asks for them. A
## branch with no `else` and a match with no catch-all get a real one, holding
## the new call, and it carries no Composer mark: a path a person asked for is
## theirs, and marking it would let a later reconnect delete it as machinery.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"

const LINEAR: Array = ["commit_ability()", "end_ability()", "return true"]
const BRANCHING: Array = ["if ready:", "\tfire()", "after()", "return true"]
const CHAINED: Array = [
	"if a:", "\tone()", "elif b:", "\ttwo()", "after()", "return true",
]
const MATCHING: Array = [
	"match state:", "\tState.A:", "\t\tone()", "\tState.B:", "\t\ttwo()",
	"after()", "return true",
]
const MERGING: Array = ["if ready:", "\tfire()", "after()", "return true"]

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


## A drag that came out of, or went into, one execution pin.
func _context(
	mode: ComposerActionMenu.Context.Mode, node_id: StringName, port_id: StringName
) -> ComposerActionMenu.Context:
	var made: ComposerActionMenu.Context = ComposerActionMenu.Context.new()
	made.mode = mode
	made.node_id = node_id
	made.port_id = port_id
	made.kind = ComposerNode.PortKind.EXECUTION
	return made


## The call the menu would offer first for an execution drag.
##
## Asked of the menu rather than named here, so a test cannot exercise a
## creation the menu would never have offered.
func _offered() -> ComposerCatalog.Entry:
	var offered: Array[ComposerCatalog.Entry] = ComposerActionMenu.compatible_entries(
		_context(ComposerActionMenu.Context.Mode.FROM_PIN, &"", &"")
	)
	return offered[0] if not offered.is_empty() else null


## Make that call from that pin, and say whether it was taken.
func _create(
	mode: ComposerActionMenu.Context.Mode, said: String, pin: StringName
) -> bool:
	var node: ComposerNode = ComposerFlowProbe.at(_document.graph(), said)
	assert_not_null(node, "there is a statement saying `%s`" % said)
	return _routes.create_and_connect(
		_offered(), _context(mode, node.id if node != null else &"", pin)
	)


func _read() -> ComposerGraph:
	return ComposerReader.read(_document.printed(), PATH)


#region Where the new statement lands
## The pins a drag can come out of that already have a path, and where each one
## puts the statement.
##
## No Match is not here: creating on it writes the catch-all that was missing, so
## afterwards the pin is gone and the arm is a case like any other. That is a
## different claim and has its own test below.
##
## The last column is the path that must be untouched by it, because "runs on
## this path" is only half the claim: a statement written into the true body and
## also reached from the false side would satisfy the first half and be wrong.
const PLACED: Array = [
	["out of a plain output", LINEAR, "commit_ability", ComposerReader.EXEC_OUT,
		"end_ability", ComposerReader.EXEC_IN],
	["out of a branch's True", BRANCHING, "if ready:", ComposerReader.TRUE_OUT,
		"fire()", ComposerReader.EXEC_IN],
	["out of a branch's False", BRANCHING, "if ready:", ComposerReader.FALSE_OUT,
		"after()", ComposerReader.EXEC_IN],
	["out of a False before an elif", CHAINED, "if a:", ComposerReader.FALSE_OUT,
		"if b:", ComposerReader.EXEC_IN],
	["out of one arm of a match", MATCHING, "match state:",
		StringName(ComposerReader.CASE_OUT % 0), "one()", ComposerReader.EXEC_IN],
]


func test_a_call_made_from_an_execution_pin_runs_on_that_path() -> void:
	var checked: int = 0
	for row: Array in PLACED:
		var described: String = row[0]
		var body: Array = row[1]
		var said: String = row[2]
		var pin: StringName = row[3]
		var onward: String = row[4]
		var onward_pin: StringName = row[5]

		_open(body)
		var made: String = String(_offered().type_id)

		var done: bool = _create(ComposerActionMenu.Context.Mode.FROM_PIN, said, pin)

		assert_true(done, "%s: it was made: %s" % [described, ComposerFlowProbe.body_of(_document.printed())])
		var read: ComposerGraph = _read()
		assert_true(
			ComposerFlowProbe.runs(read, said, pin, made),
			"%s: the path reaches it: %s" % [described, ComposerFlowProbe.body_of(_document.printed())]
		)
		assert_true(
			ComposerFlowProbe.runs(read, made, ComposerReader.EXEC_OUT, onward)
			or ComposerFlowProbe.at(read, onward) == null
			or read.has_connection(
				ComposerReader.wire(
					ComposerFlowProbe.at(read, made).id, ComposerReader.EXEC_OUT,
					ComposerFlowProbe.at(read, onward).id, onward_pin
				)
			),
			"%s: and what was on that path still follows it: %s" % [described, ComposerFlowProbe.body_of(_document.printed())]
		)
		assert_eq(_document.history().depth(), 1, "%s: as one step" % described)
		checked += 1
	assert_eq(checked, PLACED.size(), "every execution pin was tried")


## Dragging into an execution input puts the statement before it.
func test_a_call_made_into_an_execution_input_runs_before_it() -> void:
	_open(LINEAR)
	var made: String = String(_offered().type_id)

	var done: bool = _create(
		ComposerActionMenu.Context.Mode.TO_PIN, "end_ability", ComposerReader.EXEC_IN
	)

	assert_true(done, "it was made: %s" % ComposerFlowProbe.body_of(_document.printed()))
	var read: ComposerGraph = _read()
	assert_true(
		ComposerFlowProbe.runs(read, "commit_ability", ComposerReader.EXEC_OUT, made),
		"what ran before now runs into the new call: %s" % ComposerFlowProbe.body_of(_document.printed())
	)
	assert_true(
		ComposerFlowProbe.runs(read, made, ComposerReader.EXEC_OUT, "end_ability"),
		"and the new call runs into what it was dropped on"
	)


## An input several paths arrive at is refused, and nothing is written.
##
## The statement after an `if` is reached from the true body and from the false
## side. "Before it" then names two different places, and picking one would put
## the new call on one branch of two without saying so.
func test_a_call_made_into_a_merge_is_refused_without_writing() -> void:
	_open(MERGING)
	var before: String = _document.printed()

	var done: bool = _create(
		ComposerActionMenu.Context.Mode.TO_PIN, "after()", ComposerReader.EXEC_IN
	)

	assert_false(done, "there is no single place before a merge")
	assert_signal_emitted_with_parameters(
		_routes, "refused", [ComposerCreation.AMBIGUOUS_MERGE], 0
	)
	assert_eq(_document.printed(), before, "and the file is untouched")
	assert_eq(_document.history().depth(), 0, "with nothing to undo")
#endregion


#region What the new path is written as
## A branch with no `else` gets a real one, and it is not marked as machinery.
func test_creating_on_a_false_path_writes_an_else_that_is_not_machinery() -> void:
	_open(BRANCHING)

	assert_true(
		_create(
			ComposerActionMenu.Context.Mode.FROM_PIN, "if ready:", ComposerReader.FALSE_OUT
		),
		"it was made"
	)

	assert_true(_document.printed().contains("\telse:"), "an else: %s" % ComposerFlowProbe.body_of(_document.printed()))
	assert_false(
		_document.printed().contains(ComposerSubset.FLOW_ELSE_MARK),
		"and it is the person's, not machinery this tool may take away later"
	)
	assert_true(
		ComposerFlowProbe.runs(_read(), "if ready:", ComposerReader.TRUE_OUT, "fire()"),
		"the true path is untouched"
	)


## A match with no catch-all gets a real `_:`, unmarked, as its last arm.
func test_creating_on_the_no_match_path_writes_a_catch_all() -> void:
	_open(MATCHING)
	var made: String = String(_offered().type_id)

	assert_true(
		_create(
			ComposerActionMenu.Context.Mode.FROM_PIN,
			"match state:",
			ComposerReader.UNMATCHED_OUT
		),
		"it was made"
	)

	assert_true(_document.printed().contains("\t\t_:"), "a catch-all: %s" % ComposerFlowProbe.body_of(_document.printed()))
	assert_false(
		_document.printed().contains(ComposerSubset.FLOW_DEFAULT_MARK),
		"unmarked, because the person asked for it"
	)
	var read: ComposerGraph = _read()
	assert_true(
		ComposerFlowProbe.runs(read, "match state:", StringName(ComposerReader.CASE_OUT % 2), made),
		"and the new call is what that arm runs: %s" % ComposerFlowProbe.body_of(_document.printed())
	)


## Writing into the false side of an `elif` says the same thing the long way.
##
## `elif b:` *is* the false path, so there is nowhere to put a statement that
## runs before `b` is asked. The chain is written out as a nested `else: if`,
## which is the same ability, and the new call goes in front of the branch.
func test_creating_before_an_elif_writes_the_chain_out_long() -> void:
	_open(CHAINED)
	var made: String = String(_offered().type_id)

	assert_true(
		_create(ComposerActionMenu.Context.Mode.FROM_PIN, "if a:", ComposerReader.FALSE_OUT),
		"it was made"
	)

	var read: ComposerGraph = _read()
	assert_false(_document.printed().contains("elif"), "no elif is left: %s" % ComposerFlowProbe.body_of(_document.printed()))
	assert_true(
		ComposerFlowProbe.runs(read, "if a:", ComposerReader.FALSE_OUT, made),
		"the false path reaches the new call"
	)
	assert_true(
		ComposerFlowProbe.runs(read, made, ComposerReader.EXEC_OUT, "if b:"),
		"which then asks what the elif asked"
	)
	assert_true(
		ComposerFlowProbe.runs(read, "if a:", ComposerReader.TRUE_OUT, "one()"), "and the true path is untouched"
	)
#endregion


#region One thing to take back
## The statement, the path it is on and where the card sits are one commit.
func test_the_call_its_path_and_its_position_are_one_step() -> void:
	_open(LINEAR)
	var before: String = _document.printed()
	var node: ComposerNode = ComposerFlowProbe.at(_document.graph(), "commit_ability")
	var context: ComposerActionMenu.Context = _context(
		ComposerActionMenu.Context.Mode.FROM_PIN, node.id, ComposerReader.EXEC_OUT
	)
	context.graph_position = Vector2(320.0, 96.0)

	assert_true(_routes.create_and_connect(_offered(), context), "it was made")

	assert_eq(_document.history().depth(), 1, "one step")
	assert_true(
		_document.printed().contains(ComposerLayoutMetadata.PREFIX),
		"and the position was written in the same one: %s" % ComposerFlowProbe.body_of(_document.printed())
	)

	_document.undo()

	assert_eq(_document.printed(), before, "taking it back removes all three")
#endregion
