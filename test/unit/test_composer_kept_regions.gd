## A region the Composer cannot read, once it is on screen and being saved.
##
## The reader's side of this is in `test_composer_ir.gd`: where a region starts,
## where it ends, and why it is one. This is what happens to it afterwards - it
## is drawn, it offers nothing, and it comes back out of a save exactly as it
## went in.
##
## The last of those is the promise that matters. "The tool refuses to touch
## this" was the old answer and it cost a person the whole ability; "the tool
## writes it back byte for byte" is worth more and is harder to keep, so it is
## asserted twice: once on a real save, and once by forcing the failure it
## guards against.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/kept.gd"
const SOURCE: String = """extends GameplayAbility


func _activate_ability() -> bool:
	commit_ability()
	return true
"""

## The same ability with a loop where the commit was.
const WITH_A_LOOP: String = """extends GameplayAbility


func _activate_ability() -> bool:
	for target: Node in targets:
		apply_gameplay_effect(burning, target)
	return true
"""


#region Getting there
func _read(source: String) -> ComposerGraph:
	return ComposerReader.read(source, PATH)


func _kept_in(graph: ComposerGraph) -> ComposerNode:
	for node: ComposerNode in graph.nodes:
		if node.opaque:
			return node
	return null
#endregion


#region Drawn, and offering nothing
## A region is on the canvas rather than hidden.
##
## Hidden is the dangerous option: a region nobody can see is one somebody
## deletes by editing around a gap they did not know was there.
func test_a_region_it_cannot_read_is_drawn() -> void:
	var graph: ComposerGraph = _read(WITH_A_LOOP)

	assert_true(graph.is_editable(), "the ability is open")
	assert_not_null(_kept_in(graph), "and the loop is a card on it")


## And there is nothing on that card to change.
##
## A card that let a person retype what the tool could not read would eventually
## retype it wrong - so it carries no fields, claims no catalog entry, and says
## which region it is by showing the line it was written as.
func test_a_region_offers_nothing_to_change() -> void:
	var kept: ComposerNode = _kept_in(_read(WITH_A_LOOP))

	assert_eq(kept.fields.size(), 0, "nothing to type into")
	assert_null(kept.entry, "nothing claims to know which call it is")
	assert_true(kept.text.begins_with("for "), "and it shows what it is")


## It runs where it is written, so a run of control goes in and comes out.
##
## Without those two pins the statements on either side of it would have nothing
## to join to, and a body with a loop in the middle would draw as two halves
## with a hole between them.
func test_a_region_takes_a_run_of_control_and_hands_one_on() -> void:
	var kept: ComposerNode = _kept_in(_read(WITH_A_LOOP))

	assert_not_null(kept.find_port(&"exec_in"), "something can reach it")
	assert_not_null(kept.find_port(&"exec_out"), "and it leads somewhere")
#endregion


#region Written back exactly
## A save puts the region back byte for byte.
func test_a_region_the_reader_kept_is_written_back_exactly() -> void:
	var graph: ComposerGraph = _read(WITH_A_LOOP)

	var result: ComposerWriter.Result = ComposerWriter.apply(graph, WITH_A_LOOP)

	assert_true(result.is_ok(), "written: %s" % [
		result.refusal.message if result.refusal != null else ""
	])
	assert_eq(result.text, WITH_A_LOOP, "byte for byte")


## And if anything ever changed one, the save is refused rather than made.
##
## The net under the promise above. Nothing in the writer rewrites a kept region
## today - a card with no model behind it is reprinted from its own lines - but
## "nothing does this today" is not a guarantee, and what it guards against is a
## save that quietly reindents or shortens code the tool has just said it did
## not read. Forced here by altering the lines the node holds, which is what any
## future path to this bug would amount to.
func test_a_save_that_would_change_a_region_is_refused() -> void:
	var graph: ComposerGraph = _read(WITH_A_LOOP)
	_kept_in(graph).source_text = PackedStringArray(["	for target: Node in targets:"])

	var result: ComposerWriter.Result = ComposerWriter.apply(graph, WITH_A_LOOP)

	assert_false(result.is_ok(), "refused")
	assert_true(
		result.refusal.message.contains("does not read"),
		"saying which promise was about to be broken: %s" % result.refusal.message
	)


## An ability with nothing to keep is unaffected by any of it.
##
## The check the writer gained looks for regions in the source it was given, so
## a body without one has to pass through it untouched rather than be refused
## for having nothing to find.
func test_an_ability_with_no_region_saves_exactly_as_it_did() -> void:
	var graph: ComposerGraph = _read(SOURCE)

	var result: ComposerWriter.Result = ComposerWriter.apply(graph, SOURCE)

	assert_true(result.is_ok(), "written")
	assert_eq(result.text, SOURCE, "byte for byte")
#endregion
