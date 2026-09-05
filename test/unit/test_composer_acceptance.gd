## The five abilities the plan draws, drawn.
##
## Every other battery asks about one rule. These ask what a person actually
## sees: here is an ability, here is the graph it must come out as, pin by pin
## and cable by cable. Section 56 writes them as diagrams; this is those diagrams
## as assertions, which is the only form of them that can fail.
##
## The whole shape is asserted, not a corner of it. What goes wrong in a
## projection is an extra cable or a missing one, and a test that only asks about
## the cables it expects cannot see either.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"


#region Getting there
func _read(statements: Array) -> ComposerGraph:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	return ComposerReader.read(HEAD + body, PATH)


## Every execution link, written as `Title.pin -> Title`, sorted.
##
## Sorted so the assertion is about the graph and not about the order the reader
## happened to build it in.
func _running(graph: ComposerGraph) -> Array[String]:
	var said: Array[String] = []
	for wire: ComposerGraph.Connection in graph.execution_connections():
		said.append("%s.%s -> %s" % [
			_titled(graph, wire.from_node), wire.from_port, _titled(graph, wire.to_node)
		])
	said.sort()
	return said


## Every value cable, the same way.
func _feeding(graph: ComposerGraph) -> Array[String]:
	var said: Array[String] = []
	for wire: ComposerGraph.Connection in graph.data_connections():
		said.append("%s -> %s.%s" % [
			_titled(graph, wire.from_node), _titled(graph, wire.to_node), wire.to_port
		])
	said.sort()
	return said


func _titled(graph: ComposerGraph, node_id: StringName) -> String:
	var node: ComposerNode = graph.find_node(node_id)
	return node.title if node != null else String(node_id)


## What one statement carries, as `Label=value`.
func _held_by(graph: ComposerGraph, said: String) -> Array[String]:
	var node: ComposerNode = ComposerFlowProbe.at(graph, said)
	var carried: Array[String] = []
	if node == null:
		return carried
	for field: ComposerNode.Field in node.fields:
		carried.append("%s=%s" % [field.label, field.display])
	return carried
#endregion


#region The five abilities
## Each ability, and every link the graph must hold for it.
##
## The blank ability is first because it is the one everybody sees before
## anything else: a new ability has to draw as a run of control from where the
## method begins to where it ends, and nothing more.
const ABILITIES: Array = [
	[
		"a new ability",
		["return true"],
		["Entry.exec_out -> End"],
	],
	[
		"one that waits",
		["await wait_delay(1.5)", "return true"],
		["Entry.exec_out -> Wait Delay", "Wait Delay.exec_out -> End"],
	],
	[
		"one that asks something",
		["if target != null:", "\texecute_cue(hit)", "end_ability()", "return true"],
		[
			"Branch.false_out -> End Ability",
			"Branch.true_out -> Execute Cue",
			"End Ability.exec_out -> End",
			"Entry.exec_out -> Branch",
			"Execute Cue.exec_out -> End Ability",
		],
	],
	[
		"one that chooses between arms",
		[
			"match state:",
			"\tState.CASTING:",
			"\t\texecute_cue(cast)",
			"\tState.IDLE:",
			"\t\tpass",
			"end_ability()",
			"return true",
		],
		[
			"End Ability.exec_out -> End",
			"Entry.exec_out -> Switch",
			"Execute Cue.exec_out -> End Ability",
			"Nothing.exec_out -> End Ability",
			"Switch.case_0 -> Execute Cue",
			"Switch.case_1 -> Nothing",
			"Switch.unmatched_out -> End Ability",
		],
	],
]


func test_every_ability_draws_the_graph_it_is() -> void:
	var checked: int = 0
	for row: Array in ABILITIES:
		var described: String = row[0]
		var body: Array = row[1]
		var running: Array = row[2]

		var graph: ComposerGraph = _read(body)

		assert_true(graph.is_editable(), "%s: it can be drawn" % described)
		assert_eq(
			Array(_running(graph)), running, "%s: and this is what runs" % described
		)
		checked += 1
	assert_eq(checked, ABILITIES.size(), "every ability was drawn")


## The end of a new ability offers what it hands back.
func test_a_new_ability_ends_holding_what_it_returns() -> void:
	var graph: ComposerGraph = _read(["return true"])

	assert_eq(
		Array(_held_by(graph, "return true")),
		["%s=true" % ComposerNodeFields.RETURN_VALUE],
		"the End carries the value, and one value"
	)


## A waiting statement carries the argument it waits on.
func test_a_wait_carries_the_time_it_waits() -> void:
	var graph: ComposerGraph = _read(["await wait_delay(1.5)", "return true"])

	assert_eq(
		Array(_held_by(graph, "wait_delay")).size(), 1, "one argument on the card"
	)
	assert_true(
		String(_held_by(graph, "wait_delay")[0]).ends_with("=1.5"),
		"holding what the file passes: %s" % [_held_by(graph, "wait_delay")]
	)


## A branch carries its condition and leaves by two named pins, never a third.
func test_a_branch_asks_something_and_leaves_two_ways() -> void:
	var graph: ComposerGraph = _read([
		"if target != null:", "\texecute_cue(hit)", "end_ability()", "return true",
	])
	var branch: ComposerNode = ComposerFlowProbe.at(graph, "if target")

	assert_eq(
		Array(_held_by(graph, "if target")),
		["%s=target != null" % ComposerNodeFields.CONDITION],
		"the condition is what the file asks"
	)
	assert_not_null(branch.find_port(ComposerReader.TRUE_OUT), "a True pin")
	assert_not_null(branch.find_port(ComposerReader.FALSE_OUT), "a False pin")
	assert_null(branch.find_port(ComposerReader.EXEC_OUT), "and no generic way out")


## A condition that is exactly a local is fed by it.
func test_a_condition_that_names_a_local_is_wired_to_it() -> void:
	var graph: ComposerGraph = _read([
		"var ready: bool = can_activate()",
		"if ready:",
		"\texecute_cue(hit)",
		"return true",
	])

	assert_eq(
		Array(_feeding(graph)),
		["Can Activate -> Branch.%s" % ComposerReader.CONDITION_IN],
		"one cable, from the value to the condition"
	)


## A match carries what it switches on, one pin per arm, and a way out when no
## arm matches.
func test_a_match_offers_every_arm_and_the_way_out_of_none() -> void:
	var graph: ComposerGraph = _read([
		"match state:",
		"\tState.CASTING:",
		"\t\texecute_cue(cast)",
		"\tState.IDLE:",
		"\t\tpass",
		"end_ability()",
		"return true",
	])
	var switch: ComposerNode = ComposerFlowProbe.at(graph, "match state:")

	assert_eq(
		Array(_held_by(graph, "match state:")),
		["%s=state" % ComposerNodeFields.VALUE],
		"the value it switches on"
	)
	assert_eq(
		switch.find_port(StringName(ComposerReader.CASE_OUT % 0)).label,
		"State.CASTING",
		"the first arm, named as the file names it"
	)
	assert_eq(
		switch.find_port(StringName(ComposerReader.CASE_OUT % 1)).label,
		"State.IDLE",
		"and the second"
	)
	assert_not_null(
		switch.find_port(ComposerReader.UNMATCHED_OUT), "and the way out of neither"
	)
#endregion
