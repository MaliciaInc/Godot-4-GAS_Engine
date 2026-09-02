## Writing a graph back into the file it came from.
##
## Two tests here are the product. One reads a file and writes it back and
## demands the bytes are identical; the other hands the writer a graph whose
## printed form would read back as something else and demands it refuses. A
## writer that fails either does not damage files loudly - it damages them
## quietly, and the damage is found when an ability misbehaves in a game.
##
## @meta_license: MIT
extends GutTest

const PATH: String = "res://abilities/fireball.gd"

const SOURCE: String = """## A hand-written ability.
class_name Fireball extends GameplayAbility

@export var burning: GameplayEffect


func _activate_ability() -> void:
	commit_ability()

	# Aim before spending anything.
	var target: Node = await wait_target_data()
	apply_effect_to_target_data(burning, target)
	end_ability()


func _on_removed() -> void:
	pass
"""


func _read() -> ComposerGraph:
	return ComposerReader.read(SOURCE, PATH)


#region The round trip
## Read, write, and the file is the same bytes.
##
## This is what "the graph is a view of the file" has to mean in practice. A
## save that reformats, reorders or re-spaces anything is a save people learn
## not to make - and the first thing they stop trusting is the tool, not the
## formatting.
func test_reading_a_file_and_writing_it_back_changes_nothing() -> void:
	var result: ComposerWriter.Result = ComposerWriter.apply(_read(), SOURCE)

	assert_true(result.is_ok(), "it accepted the write")
	assert_eq(result.text, SOURCE, "byte for byte, including the blank lines")


## Everything outside the body is copied, never rewritten. The comment at the
## top, the export, and the helper below all survive because the writer never
## treats them as text it may change.
func test_everything_outside_the_body_survives_untouched() -> void:
	var result: ComposerWriter.Result = ComposerWriter.apply(_read(), SOURCE)

	assert_true(result.text.begins_with("## A hand-written ability."), "the header")
	assert_true(result.text.contains("@export var burning: GameplayEffect"), "the export")
	assert_true(result.text.contains("func _on_removed() -> void:"), "the helper below")


## A comment inside the body belongs to the statement under it, and comes back
## in the same place rather than being dropped on the first save.
func test_a_comment_inside_the_body_comes_back_where_it_was() -> void:
	var result: ComposerWriter.Result = ComposerWriter.apply(_read(), SOURCE)

	assert_true(
		result.text.contains("\t# Aim before spending anything.\n\tvar target:"),
		"still above the statement it describes"
	)
#endregion


## A corpus, not one file.
##
## One example proves the machinery runs; a corpus proves the promise. Each of
## these is a shape a person writes without thinking about it - a branch, a
## match, a run of blank lines, a comment against the closing statement - and
## every one has to survive a save unchanged. The round trip is the product, so
## it is checked against the shapes the product will meet.
##
## Written as lines joined at runtime rather than as escaped literals: a corpus
## about whitespace is the last place to hide whitespace inside escapes.
func test_a_corpus_of_bodies_all_survive_a_round_trip() -> void:
	var bodies: Array[Array] = [
		["\tcommit_ability()"],
		["\tcommit_ability()", "\tend_ability()"],
		["\tif is_ready:", "\t\tcommit_ability()", "\tend_ability()"],
		["\tmatch policy:", "\t\tPolicy.INSTANT:", "\t\t\tcommit_ability()"],
		["\tcommit_ability()", "", "", "\tend_ability()"],
		["\t# why", "\tcommit_ability()", "\t# and why not", "\tend_ability()"],
		["\tvar target: Node = await wait_target_data()", "\tapply(burning, target)"],
	]

	for body: Array in bodies:
		var written: PackedStringArray = PackedStringArray([
			"extends GameplayAbility", "", "",
			"func _activate_ability() -> void:",
		])
		written.append_array(PackedStringArray(body))
		written.append("")
		var source: String = "\n".join(written)

		var result: ComposerWriter.Result = ComposerWriter.apply(
			ComposerReader.read(source, PATH), source
		)
		assert_true(result.is_ok(), "accepted: %s" % [body])
		assert_eq(result.text, source, "unchanged: %s" % [body])

#region Refusing to write
## Nothing reaches disk unverified.
##
## The graph here says it applies an effect; the node's remembered text says it
## commits. Printing the text and reading it back produces a different graph, and
## that mismatch is the whole point of the check - a printer that silently drops
## or reorders something makes a file that compiles and no longer does what the
## graph said.
func test_a_write_that_would_not_read_back_the_same_is_refused() -> void:
	var graph: ComposerGraph = _read()
	graph.nodes[0].type_id = &"apply_gameplay_effect"

	var result: ComposerWriter.Result = ComposerWriter.apply(graph, SOURCE)

	assert_false(result.is_ok(), "it did not hand over text")
	assert_eq(result.text, "", "and there is nothing to write by accident")
	assert_true(
		result.refusal.message.contains("not what it was given"),
		"saying what went wrong: %s" % result.refusal.message
	)


## A file the reader could not draw is not one the writer may touch. Opening
## read-only has to mean read-only all the way down.
func test_an_unreadable_file_is_never_written() -> void:
	var refused: String = SOURCE.replace(
		"\tcommit_ability()", "\tfor target in targets:\n\t\tpass"
	)
	var graph: ComposerGraph = ComposerReader.read(refused, PATH)

	var result: ComposerWriter.Result = ComposerWriter.apply(graph, refused)
	assert_false(result.is_ok(), "read-only means the writer stays out too")


func test_a_script_with_no_entry_point_is_refused() -> void:
	var graph: ComposerGraph = _read()
	var result: ComposerWriter.Result = ComposerWriter.apply(
		graph, "extends GameplayAbility\n"
	)

	assert_false(result.is_ok(), "there is nowhere to write")
	assert_true(
		result.refusal.message.contains(ComposerSubset.ENTRY_POINT), "and it says so"
	)
#endregion


#region Rebuilding an edited node
## Only a dirty node is rebuilt. Everything else keeps its own text, which is
## what makes a save a change to one statement rather than to the whole file.
func test_only_an_edited_node_is_rebuilt_from_the_model() -> void:
	var graph: ComposerGraph = _read()
	var last: ComposerNode = graph.nodes[graph.nodes.size() - 1]
	last.dirty = true

	var body: PackedStringArray = ComposerWriter.print_body(graph)

	assert_true(
		"\t# Aim before spending anything." in body,
		"the untouched statements kept their comment"
	)
	assert_eq(body[body.size() - 1], "\tend_ability()", "and the edited one was printed")


func test_a_rendered_statement_keeps_its_arguments_in_order() -> void:
	var graph: ComposerGraph = _read()
	var node: ComposerNode = graph.find_node(graph.nodes[2].id)

	assert_eq(
		ComposerWriter.render(node), "\tapply_effect_to_target_data(burning, target)",
		"the call, its arguments, and the indentation it sits at"
	)
#endregion


#region The signature
## Structure, not line numbers.
##
## Comparing spans would refuse every real edit - a statement that moved is the
## normal outcome of editing - while catching nothing that matters.
func test_moving_a_statement_does_not_change_what_the_graph_is() -> void:
	var spaced: String = SOURCE.replace(
		"\tcommit_ability()", "\n\n\tcommit_ability()"
	)

	assert_eq(
		ComposerWriter.signature(_read()),
		ComposerWriter.signature(ComposerReader.read(spaced, PATH)),
		"blank lines are not part of what an ability does"
	)


func test_changing_an_argument_changes_what_the_graph_is() -> void:
	var graph: ComposerGraph = _read()
	var before: String = ComposerWriter.signature(graph)
	graph.nodes[2].fields[0].display = "freezing"

	assert_ne(
		ComposerWriter.signature(graph), before,
		"a different effect is a different ability"
	)
#endregion
