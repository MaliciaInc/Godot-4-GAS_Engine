## What the Composer says is wrong with an ability.
##
## Two claims are worth more than the rest here. The first is that a warning is
## only ever printed about code that is actually odd: half these tests hand the
## validator correct GDScript and demand silence, because a tool that marks
## working code teaches people to stop reading the panel, and after that it does
## not matter how good the real findings are.
##
## The second is that the dot on a card and the row in the panel are one answer
## rendered twice. A card sitting clean beside a row complaining about it is the
## contradiction that makes someone stop believing either.
##
## @meta_license: MIT
extends GutTest

const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> void:\n"


func _read(body: PackedStringArray) -> ComposerGraph:
	return ComposerReader.read(HEAD + "\t" + "\n\t".join(body) + "\n", "res://a.gd")


func _messages(graph: ComposerGraph) -> PackedStringArray:
	var said: PackedStringArray = PackedStringArray()
	for entry: ComposerGraph.Diagnostic in graph.diagnostics:
		said.append(entry.message)
	return said


#region Arguments the call never passed
## The engine says how many arguments are required; this only reports the gap.
func test_a_required_argument_left_out_is_an_error() -> void:
	var graph: ComposerGraph = _read(PackedStringArray(["add_tag()"]))

	assert_eq(graph.diagnostics.size(), 1, "one finding: %s" % [_messages(graph)])
	assert_eq(
		graph.diagnostics[0].severity, ComposerGraph.Severity.ERROR, "the file will not run"
	)
	assert_true(graph.diagnostics[0].message.contains("Tag"), "naming what is missing")


## The panel and the card say the same thing, because they are the same pass.
func test_the_gap_reaches_the_card_as_a_field() -> void:
	var node: ComposerNode = _read(PackedStringArray(["add_tag()"])).nodes[0]

	assert_eq(node.fields.size(), 1, "the card grew the argument it is short")
	assert_eq(node.fields[0].label, "Tag", "named by the engine")
	assert_eq(node.fields[0].source, ComposerNode.ValueSource.MISSING, "and marked absent")
	assert_eq(node.state, ComposerNode.State.ERROR, "and the dot agrees with the row")


## `apply_gameplay_effect` takes three and defaults two. A call passing one has
## said everything it needed to, and marking it would put an error on most
## correct statements in a file.
func test_an_argument_with_a_default_is_not_a_gap() -> void:
	var graph: ComposerGraph = _read(PackedStringArray(["apply_gameplay_effect(fire)"]))

	assert_eq(graph.diagnostics.size(), 0, "nothing to say: %s" % [_messages(graph)])
	assert_eq(graph.nodes[0].fields.size(), 1, "and no field was invented")


## A call outside the catalog has no declared arity, so there is nothing to
## check. Guessing one would refuse a person their own helper.
func test_a_call_the_catalog_does_not_offer_is_left_alone() -> void:
	var graph: ComposerGraph = _read(PackedStringArray(["my_own_helper()"]))

	assert_eq(graph.diagnostics.size(), 0, "unknown is not wrong: %s" % [_messages(graph)])
#endregion


#region Wires that do not fit
func test_a_value_landing_in_a_slot_that_refuses_it_is_an_error() -> void:
	var graph: ComposerGraph = _read(PackedStringArray([
		"var target: GameplayAbilityTargetData = await wait_target_data()",
		"add_tag(target)",
	]))

	assert_eq(graph.diagnostics.size(), 1, "one finding: %s" % [_messages(graph)])
	var said: String = graph.diagnostics[0].message
	assert_true(said.contains("GameplayAbilityTargetData"), "what was offered: %s" % said)
	assert_true(said.contains("StringName"), "and what was wanted: %s" % said)


## Blamed on the statement that will not compile, not on the one that produced
## the value - that is the line someone has to open.
func test_the_refusal_is_reported_against_the_statement_that_receives_it() -> void:
	var graph: ComposerGraph = _read(PackedStringArray([
		"var target: GameplayAbilityTargetData = await wait_target_data()",
		"add_tag(target)",
	]))

	assert_eq(
		graph.diagnostics[0].node_id, graph.nodes[1].id, "the call, not the declaration"
	)
	assert_eq(graph.nodes[1].state, ComposerNode.State.ERROR, "and its dot says so")
	assert_eq(graph.nodes[0].state, ComposerNode.State.CLEAN, "while the source is fine")


func test_a_value_landing_where_it_fits_is_not_reported() -> void:
	var graph: ComposerGraph = _read(PackedStringArray([
		"var target: GameplayAbilityTargetData = await wait_target_data()",
		"apply_effect_to_targets(fire, target)",
	]))

	assert_eq(graph.diagnostics.size(), 0, "the types agree: %s" % [_messages(graph)])
#endregion


#region Values nobody reads
func test_a_local_no_later_statement_names_is_a_warning() -> void:
	var graph: ComposerGraph = _read(PackedStringArray([
		"var level: float = get_ability_level()",
		"commit_ability()",
	]))

	assert_eq(graph.diagnostics.size(), 1, "one finding: %s" % [_messages(graph)])
	assert_eq(
		graph.diagnostics[0].severity, ComposerGraph.Severity.WARNING, "odd, not broken"
	)
	assert_true(graph.diagnostics[0].message.contains("level"), "naming the value")


## The check that is easy to get wrong.
##
## Decided on the text of the later statements, not on the cables. A cable is
## drawn wherever an argument depends on a local, expression and all - but an
## argument is not the only way to read one. `if paid.is_ok():` reads `paid` in
## a branch, which has no argument for a cable to land on, and deciding from the
## cables would call that local dead. One false warning costs more trust than a
## real one buys.
func test_a_local_read_inside_an_expression_is_not_reported() -> void:
	var graph: ComposerGraph = _read(PackedStringArray([
		"var level: float = get_ability_level()",
		"apply_gameplay_effect(fire, caster, level + 1.0)",
	]))

	assert_eq(graph.diagnostics.size(), 0, "it is read: %s" % [_messages(graph)])


## And one read where no cable can reach is read all the same.
func test_a_local_read_only_by_a_branch_is_not_reported() -> void:
	var graph: ComposerGraph = _read(PackedStringArray([
		"var paid: AbilityCommitResult = commit_ability()",
		"if not paid.is_ok():",
		"	end_ability()",
	]))

	var cabled: int = 0
	for wire: ComposerGraph.Connection in graph.connections:
		cabled += 1 if wire.from_port == ComposerReader.VALUE_OUT else 0
	assert_eq(cabled, 0, "a branch has no argument for a cable to land on")
	assert_eq(graph.diagnostics.size(), 0, "and it is read anyway: %s" % [_messages(graph)])


func test_a_name_buried_in_a_longer_one_does_not_count_as_a_read() -> void:
	var graph: ComposerGraph = _read(PackedStringArray([
		"var level: float = get_ability_level()",
		"execute_cue(level_up_cue)",
	]))

	assert_eq(graph.diagnostics.size(), 1, "level_up_cue is not level: %s" % [_messages(graph)])
	assert_true(graph.diagnostics[0].message.contains("never read"), "said plainly")
#endregion


#region One answer, rendered twice
## Every finding reaches its card, and every card without a finding stays clean.
## Checked over a body carrying one of each kind rather than asserted once.
func test_no_card_disagrees_with_the_panel() -> void:
	var graph: ComposerGraph = _read(PackedStringArray([
		"var level: float = get_ability_level()",
		"add_tag()",
		"commit_ability()",
	]))

	var blamed: Array[StringName] = []
	for entry: ComposerGraph.Diagnostic in graph.diagnostics:
		blamed.append(entry.node_id)
	assert_gt(blamed.size(), 1, "the body is wrong in more than one way")

	for node: ComposerNode in graph.nodes:
		var marked: bool = node.state != ComposerNode.State.CLEAN
		assert_eq(marked, blamed.has(node.id), "%s: dot and panel agree" % node.title)


## A card carrying both shows the error. Someone scanning for red should not
## have to discover that the amber one is also broken.
func test_an_error_outranks_a_warning_on_the_same_card() -> void:
	var graph: ComposerGraph = _read(PackedStringArray([
		"var result: GameplayTargetApplicationResult = await apply_effect_to_targets(fire)",
	]))

	assert_eq(graph.diagnostics.size(), 2, "short an argument, and never read")
	assert_eq(graph.nodes[0].state, ComposerNode.State.ERROR, "the louder of the two")


## Re-reading a file someone just edited comes through here. A second pass that
## added the same gap again would report it twice and grow the card each time.
func test_looking_twice_says_the_same_thing() -> void:
	var graph: ComposerGraph = _read(PackedStringArray(["add_tag()"]))
	var first: PackedStringArray = _messages(graph)
	var fields: int = graph.nodes[0].fields.size()

	ComposerValidator.apply(graph)

	assert_eq(_messages(graph), first, "the same findings")
	assert_eq(graph.nodes[0].fields.size(), fields, "and the card did not grow")
#endregion


#region Silence
func test_an_ability_with_nothing_wrong_reports_nothing() -> void:
	var graph: ComposerGraph = _read(PackedStringArray([
		"commit_ability()",
		"var target: GameplayAbilityTargetData = await wait_target_data()",
		"apply_effect_to_targets(fire, target)",
		"end_ability()",
	]))

	assert_eq(graph.diagnostics.size(), 0, "a correct ability: %s" % [_messages(graph)])
	for node: ComposerNode in graph.nodes:
		assert_eq(node.state, ComposerNode.State.CLEAN, "%s carries no mark" % node.title)


## A file the subset cannot draw is not a file with mistakes in it. Adding
## findings on top of the refusal would tell someone their working code is
## broken because this tool cannot read it.
func test_a_file_outside_the_subset_is_not_second_guessed() -> void:
	var graph: ComposerGraph = _read(PackedStringArray(["for step in 3:", "\tadd_tag()"]))

	assert_eq(graph.diagnostics.size(), 1, "only the refusal: %s" % [_messages(graph)])
	assert_eq(
		graph.diagnostics[0].severity,
		ComposerGraph.Severity.NOT_REPRESENTABLE,
		"which is not an error in the file"
	)
#endregion
