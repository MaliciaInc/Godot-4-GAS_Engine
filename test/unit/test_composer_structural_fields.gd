## The values a structural statement carries, as fields a person can edit.
##
## A `return true` is not only an End: the `true` is a value, and a card that
## hides it is a card somebody cannot change the outcome from. The same goes for
## the condition of an `if` and the value a `match` switches on. Each of them is
## read into a field with the whole contract a call argument has - a type, a
## default, whether it may be edited - so one editor serves all of them, and a
## data pin that names its field so a controller never parses a number off a
## pin's name.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/probe.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"

## The same method without saying what it returns.
const HEAD_UNTYPED: String = "extends GameplayAbility\n\n\nfunc _activate_ability():\n"


func _read(statements: Array, head: String = HEAD) -> ComposerGraph:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	return ComposerReader.read(head + body, PATH)


func _titled(graph: ComposerGraph, title: String) -> ComposerNode:
	for node: ComposerNode in ComposerProjection.statements(graph):
		if node.title == title:
			return node
	return null


func _containing(graph: ComposerGraph, written: String) -> ComposerNode:
	for node: ComposerNode in ComposerProjection.statements(graph):
		if node.text.contains(written):
			return node
	return null


#region End has a Return Value
## `return true` carries its value as a field.
func test_end_has_a_return_value_field_for_return_true() -> void:
	var graph: ComposerGraph = _read(["return true"])
	var end: ComposerNode = _titled(graph, "End")

	assert_not_null(end, "the return is drawn as End")
	assert_eq(end.fields.size(), 1, "with one field")
	assert_eq(end.fields[0].label, ComposerNodeFields.RETURN_VALUE, "called Return Value")
	assert_eq(end.fields[0].display, "true", "holding what the file returns")
	assert_true(end.fields[0].editable, "and a person may change it")


## A bare `return` hands nothing back, so there is nothing to edit.
func test_a_bare_return_carries_no_field() -> void:
	var graph: ComposerGraph = _read(["return"], HEAD_UNTYPED)
	var end: ComposerNode = _titled(graph, "End")

	assert_not_null(end, "the return is still the End")
	assert_eq(end.fields.size(), 0, "with nothing to hold")
	assert_null(end.find_port(ComposerReader.RETURN_VALUE_IN), "and no pin for it")


## The Return Value is typed by what the method says it returns.
func test_the_return_value_is_typed_by_the_signature() -> void:
	var typed: ComposerNode = _titled(_read(["return true"]), "End")
	var untyped: ComposerNode = _titled(_read(["return true"], HEAD_UNTYPED), "End")

	assert_eq(typed.fields[0].type_name, ComposerTypes.BOOL, "the signature says bool")
	assert_eq(
		typed.fields[0].default_expression,
		ComposerTypes.default_expression(ComposerTypes.BOOL),
		"and its default is the type's"
	)
	assert_eq(untyped.fields[0].type_name, &"", "no signature, no type")


## The return type is read off the signature line, and only off it.
func test_the_return_type_is_read_off_the_entry_point() -> void:
	assert_eq(
		ComposerSubset.entry_return_type(HEAD.split("\n")), ComposerTypes.BOOL, "-> bool"
	)
	assert_eq(
		ComposerSubset.entry_return_type(HEAD_UNTYPED.split("\n")), &"", "no arrow, no type"
	)
	assert_eq(
		ComposerSubset.entry_return_type(
			"func _activate_ability() -> GameplayAbilityTargetData:".split("\n")
		),
		&"GameplayAbilityTargetData",
		"a class name comes through whole"
	)
	assert_eq(
		ComposerSubset.entry_return_type("func other() -> bool:".split("\n")), &"",
		"some other method's signature is not this one"
	)


## The End has a pin for its value and never a way out.
func test_end_has_a_return_value_pin_and_no_exec_output() -> void:
	var end: ComposerNode = _titled(_read(["return true"]), "End")
	var pin: ComposerNode.Port = end.find_port(ComposerReader.RETURN_VALUE_IN)

	assert_not_null(pin, "the value has a pin")
	assert_eq(pin.field_index, 0, "which names its field")
	assert_eq(pin.kind, ComposerNode.PortKind.DATA, "and carries a value")
	assert_eq(pin.direction, ComposerNode.PortDirection.INPUT, "in")
	assert_null(end.find_port(ComposerReader.EXEC_OUT), "and nothing runs after the end")
#endregion


#region Branch has a Condition
func test_a_branch_carries_its_condition_as_a_field() -> void:
	var branch: ComposerNode = _titled(
		_read(["if ready and has_target:", "\tfire()", "return true"]), "Branch"
	)

	assert_not_null(branch, "the if is drawn as a Branch")
	assert_eq(branch.fields.size(), 1, "with one field")
	var condition: ComposerNode.Field = branch.fields[0]
	assert_eq(condition.label, ComposerNodeFields.CONDITION)
	assert_eq(condition.type_name, ComposerTypes.BOOL, "a condition is a bool")
	assert_eq(condition.display, "ready and has_target", "holding exactly what is tested")
	assert_eq(condition.source, ComposerNode.ValueSource.LITERAL, "written in the file")
	assert_eq(
		condition.default_expression,
		ComposerTypes.default_expression(ComposerTypes.BOOL),
		"and falling back to false"
	)
	assert_true(condition.editable, "which a person may change")


func test_the_condition_has_a_data_input_that_names_its_field() -> void:
	var branch: ComposerNode = _titled(_read(["if ready:", "\tfire()", "return true"]), "Branch")
	var pin: ComposerNode.Port = branch.find_port(ComposerReader.CONDITION_IN)

	assert_not_null(pin, "the condition has a pin")
	assert_eq(pin.field_index, 0, "which names its field")
	assert_eq(pin.type_name, ComposerTypes.BOOL, "typed like it")
	assert_eq(pin.direction, ComposerNode.PortDirection.INPUT, "and taking a value in")
	assert_null(branch.find_port(StringName(ComposerReader.ARGUMENT % 0)), "not numbered")


## `elif` is a Branch a person can see. `else:` tests nothing and is not drawn.
func test_an_elif_is_a_visible_branch_and_an_else_is_not() -> void:
	var graph: ComposerGraph = _read([
		"if a:", "\tone()", "elif b:", "\ttwo()", "else:", "\tthree()", "return true"
	])
	var second: ComposerNode = _containing(graph, "elif b:")
	var otherwise: ComposerNode = _containing(graph, "else:")

	assert_eq(second.projection_kind, ComposerNode.ProjectionKind.BRANCH, "elif is a Branch")
	assert_true(second.visible_in_graph, "drawn")
	assert_eq(second.title, "Branch", "and titled as one")
	assert_eq(second.fields[0].display, "b", "with its own condition")
	assert_eq(otherwise.projection_kind, ComposerNode.ProjectionKind.SUPPORT, "else is support")
	assert_false(otherwise.visible_in_graph, "which nobody is shown")
#endregion


#region Switch has a Value
func test_a_match_carries_the_value_it_switches_on() -> void:
	var switch: ComposerNode = _titled(
		_read(["match state:", "\tState.A:", "\t\tone()", "return true"]), "Switch"
	)

	assert_not_null(switch, "the match is drawn as a Switch")
	assert_eq(switch.fields.size(), 1, "with one field")
	assert_eq(switch.fields[0].label, ComposerNodeFields.VALUE)
	assert_eq(switch.fields[0].type_name, ComposerTypes.VARIANT, "the language compares anything")
	assert_eq(switch.fields[0].display, "state", "holding what is switched on")
	assert_eq(switch.fields[0].default_expression, ComposerTypes.NOTHING, "falling back to null")
	var pin: ComposerNode.Port = switch.find_port(ComposerReader.MATCH_VALUE_IN)
	assert_not_null(pin, "and a pin for it")
	assert_eq(pin.field_index, 0, "naming its field")
#endregion


#region Every data pin names its field
func test_a_call_argument_pin_names_the_field_it_stands_for() -> void:
	var call: ComposerNode = _containing(
		_read(["apply_gameplay_effect(burning, owner_asc, 1.0)", "return true"]),
		"apply_gameplay_effect"
	)

	assert_eq(call.fields.size(), 3, "three arguments")
	for position: int in call.fields.size():
		var pin: ComposerNode.Port = call.find_port(StringName(ComposerReader.ARGUMENT % position))
		assert_not_null(pin, "argument %d has a pin" % position)
		assert_eq(pin.field_index, position, "which names field %d" % position)
		assert_eq(pin.label, call.fields[position].label, "by the same name")
		assert_true(call.fields[position].editable, "and the argument may be changed")
#endregion


#region Editing follows the field, not the statement
## Whether a field may be changed is the field's own word.
func test_editing_follows_the_field_contract() -> void:
	var graph: ComposerGraph = _read(["if ready:", "\tcommit_ability()", "return true"])
	var branch: ComposerNode = _titled(graph, "Branch")
	var call: ComposerNode = _containing(graph, "commit_ability")

	assert_true(branch.may_edit(branch.fields[0]), "a condition may be edited")
	assert_false(call.may_edit(null), "nothing is not a field")

	var refused: ComposerNode.Field = ComposerNode.Field.new()
	refused.editable = false
	assert_false(call.may_edit(refused), "a field the writer cannot print is left alone")

	var wired: ComposerNode.Field = ComposerNode.Field.new()
	wired.editable = true
	wired.source = ComposerNode.ValueSource.WIRED
	assert_true(call.may_edit(wired), "a wired value may still move")
	assert_false(call.may_type(wired), "but not by typing over the cable")
#endregion


#region A local reaches a structural field
## What a card carries and what feeds it are the same question asked twice.
##
## `var ready: bool = can_activate()` and then `if ready:` is a value flowing
## from one statement into another - exactly what a cable draws - and it went
## undrawn because the wiring read a call's argument list and a branch has none.
## The rows are the three answers: the condition of a branch, what a return hands
## back, and an expression that only mentions the local, which is not a wire.
const REACHING: Array = [
	[
		"a branch tests a local",
		["var ready: bool = can_activate()", "if ready:", "\tcommit_ability()", "return true"],
		"if ready:",
		ComposerReader.CONDITION_IN,
		true,
	],
	[
		"an end hands a local back",
		["var done: bool = commit_ability()", "return done"],
		"return done",
		ComposerReader.RETURN_VALUE_IN,
		true,
	],
	[
		"a switch turns on a local",
		["var state: int = pick_state()", "match state:", "\tState.READY:", "\t\tone()", "return true"],
		"match state:",
		ComposerReader.MATCH_VALUE_IN,
		true,
	],
	[
		"an expression is not a cable",
		["var ready: bool = can_activate()", "if ready and armed:", "\tone()", "return true"],
		"if ready and armed:",
		ComposerReader.CONDITION_IN,
		false,
	],
]


func test_a_local_reaches_the_structural_value_that_is_exactly_it() -> void:
	var checked: int = 0
	for row: Array in REACHING:
		var described: String = row[0]
		var body: Array = row[1]
		var said: String = row[2]
		var pin: StringName = row[3]
		var wired: bool = row[4]

		var graph: ComposerGraph = _read(body)
		var node: ComposerNode = _containing(graph, said)

		assert_eq(
			graph.is_port_connected(node.id, pin),
			wired,
			"%s: the pin %s a cable" % [described, "takes" if wired else "takes no"]
		)
		assert_eq(
			node.fields[0].source == ComposerNode.ValueSource.WIRED,
			wired,
			"%s: and the field agrees with the pin" % described
		)
		checked += 1
	assert_eq(checked, REACHING.size(), "every shape was tried")


## One value passed twice draws two cables, not one.
##
## Landing only on the first slot leaves a pin somebody can see, cannot unplug
## and cannot re-point, because nothing believes there is a cable on it.
func test_a_local_passed_twice_lands_on_both_slots() -> void:
	var graph: ComposerGraph = _read([
		"var caster: AbilitySystemComponent = owner_asc",
		"pair_casters(caster, caster)",
		"return true",
	])
	var pair: ComposerNode = _containing(graph, "pair_casters")

	assert_eq(
		graph.connections_for(pair.id).size(), 4, "two values in, one run in, one run out"
	)
	assert_true(
		graph.is_port_connected(pair.id, pair.pin_for_field(0).id), "the first slot"
	)
	assert_true(
		graph.is_port_connected(pair.id, pair.pin_for_field(1).id), "and the second"
	)
#endregion
