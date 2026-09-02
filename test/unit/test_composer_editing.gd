## Typing a value, and the file it reaches.
##
## Until this, the Composer was a viewer: nothing marked a node edited, so the
## whole writer - byte-exact and verified - was built and unused.
##
## Two claims run through everything here. The first is that **some values can be
## typed and some cannot**, and which is which is a fact about the value rather
## than a guess: one that arrives on a cable is whatever the statement above
## produced, and a box offering to change it offers something that cannot be
## done. The second is that a save either leaves the file correct or leaves it
## alone - there is no third outcome.
##
## @meta_license: MIT
extends GutTest

## Real GDScript, because the reader loads the file it is handed: it resolves a
## receiver against the script the call was written in. A fixture that does not
## compile is not read the way an ability is read.
const SOURCE: String = """extends GameplayAbility

@export var burning: GameplayEffect


func _activate_ability() -> bool:
	var level: float = get_ability_level()

	# Aim before spending anything.
	owner_asc.apply_gameplay_effect(burning, owner_asc, level)
	end_ability()
	return true


func _after_removed() -> void:
	pass
"""

const OUTSIDE: String = """extends GameplayAbility


func _activate_ability() -> bool:
	for step: int in 3:
		end_ability()
	return true
"""

## A call short of a required argument, which by definition does not compile -
## so it is never written to disk. Nothing that reads it saves.
const SHORT: String = """extends GameplayAbility


func _activate_ability() -> void:
	owner_asc.add_tag()
"""

const AN_ABILITY: String = "res://addons/GAS_Engine/reference/timed_buff.gd"
const SCRATCH: String = "user://composer_editing_%d.gd"

const EFFECT: int = 0
const SOURCE_ASC: int = 1
const LEVEL: int = 2

var screen: ComposerScreen = null
var path: String = ""


func before_each() -> void:
	screen = ComposerScreen.new()
	screen.size = Vector2(1400.0, 800.0)
	add_child_autofree(screen)


func after_each() -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	path = ""
	screen = null


## A real file on disk, because a save that never touches one proves nothing.
func _open(source: String, tag: int) -> ComposerGraph:
	path = SCRATCH % tag
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	out.store_string(source)
	out.close()

	await screen.open(source, path)
	return screen.graph()


func _applied(graph: ComposerGraph) -> ComposerNode:
	for node: ComposerNode in graph.nodes:
		if node.type_id == &"apply_gameplay_effect":
			return node
	return null


#region Which values can be typed
func test_a_value_that_was_typed_can_be_typed_again() -> void:
	var graph: ComposerGraph = await _open(SOURCE, 1)
	var node: ComposerNode = _applied(graph)

	assert_not_null(node, "the statement was found by its call")
	assert_eq(node.fields[EFFECT].source, ComposerNode.ValueSource.LITERAL, "written")
	assert_true(node.may_edit(node.fields[EFFECT]), "so it can be written again")


## A value fed by a cable is not typed anywhere.
##
## `level` comes from the statement above it. Offering a box for it would offer
## something that cannot be done, and whatever was typed would be thrown away
## the next time the file was read.
func test_a_value_that_arrives_on_a_cable_cannot_be_typed() -> void:
	var graph: ComposerGraph = await _open(SOURCE, 2)
	var node: ComposerNode = _applied(graph)

	assert_eq(node.fields[LEVEL].source, ComposerNode.ValueSource.WIRED, "it is wired")
	assert_false(node.may_edit(node.fields[LEVEL]), "so it is not typed here")
	assert_true(node.may_edit(node.fields[SOURCE_ASC]), "while the one beside it is")


## A statement this cannot print back is not edited at all.
##
## A branch, a return, a wait on a signal: the writer would have to rebuild it
## from a model that never held it, so nothing about it is offered.
func test_a_statement_that_cannot_be_printed_back_is_not_edited() -> void:
	var graph: ComposerGraph = await _open(SOURCE, 3)
	var counted: int = 0

	for node: ComposerNode in graph.nodes:
		if not node.type_id.is_empty():
			continue
		counted += 1
		for field: ComposerNode.Field in node.fields:
			assert_false(node.may_edit(field), "%s offers nothing" % node.title)
	assert_gt(counted, 0, "the body has at least one of them")


## A file outside the subset opens read-only, and nothing in it is offered.
func test_nothing_is_offered_in_a_file_the_composer_cannot_draw() -> void:
	var graph: ComposerGraph = await _open(OUTSIDE, 4)

	assert_false(graph.is_editable(), "read-only: %s" % graph.blocked_reason())
	assert_eq(graph.nodes.size(), 0, "and there is nothing on the canvas to offer")
#endregion


#region Typing one
## What a typed value does, and what a wired one refuses to do.
##
## One table because they are the same gesture with opposite answers, and the
## difference is the whole point: `some but not all`. The refusal is asked of
## the screen rather than of the panel - the panel does not draw a box for a
## wired value, but a guard that lives only in the thing that draws the control
## is one the next caller walks straight past.
const EDITS: Array[Array] = [
	[EFFECT, "freezing", true, "a value somebody wrote"],
	[LEVEL, "9.0", false, "a value that arrives on a cable"],
]


func test_only_the_values_that_can_be_typed_are_changed() -> void:
	var graph: ComposerGraph = await _open(SOURCE, 5)
	var node: ComposerNode = _applied(graph)

	for row: Array in EDITS:
		var position: int = row[0]
		var written: String = row[1]
		var takes: bool = row[2]
		var described: String = row[3]
		var before: String = node.fields[position].display
		node.dirty = false

		screen._on_value_edited(node.id, position, written)
		await wait_frames(2)

		assert_eq(
			node.fields[position].display, written if takes else before,
			"%s: %s" % [described, "changes" if takes else "is left alone"]
		)
		assert_eq(node.dirty, takes, "%s: and the node says so" % described)


## A missing argument that is filled in stops being missing.
##
## The gap is the validator's doing, not the statement's. Typing into it has to
## turn it into a real argument, or the next pass strips it back out and the
## person watches what they wrote disappear.
func test_filling_in_a_missing_argument_keeps_what_was_typed() -> void:
	await screen.open(SHORT, AN_ABILITY)
	var graph: ComposerGraph = screen.graph()
	var node: ComposerNode = graph.nodes[0]

	assert_eq(node.fields[EFFECT].source, ComposerNode.ValueSource.MISSING, "a gap")
	assert_eq(graph.diagnostics.size(), 1, "and the panel says so")

	screen._on_value_edited(node.id, EFFECT, "state_burning")
	await wait_frames(2)

	# Read again: an edit replaces the graph, so the one held before it is an
	# ability that is no longer open.
	var after: ComposerNode = screen.graph().nodes[0]
	assert_eq(after.fields[EFFECT].display, "state_burning", "what was typed survived")
	assert_eq(
		after.fields[EFFECT].source, ComposerNode.ValueSource.LITERAL, "as a real argument"
	)
	assert_eq(screen.graph().diagnostics.size(), 0, "and the panel has nothing to say")


#endregion


#region Saving
func test_saving_writes_the_edit_and_leaves_the_rest_of_the_file_alone() -> void:
	var graph: ComposerGraph = await _open(SOURCE, 7)
	var node: ComposerNode = _applied(graph)
	screen._on_value_edited(node.id, EFFECT, "freezing")
	await wait_frames(2)

	var result: ComposerWriter.Result = await screen.save()

	assert_true(result.is_ok(), "saved")
	var on_disk: String = FileAccess.get_file_as_string(path)
	assert_true(
		on_disk.contains("owner_asc.apply_gameplay_effect(freezing, owner_asc, level)"),
		"the edit landed, receiver and all: %s" % on_disk
	)
	assert_true(on_disk.contains("# Aim before spending anything."), "the comment stayed")
	assert_true(on_disk.contains("func _after_removed() -> void:"), "and so did the rest")
	assert_true(on_disk.contains("@export var burning: GameplayEffect"), "and the exports")


## Saving twice without touching anything changes nothing the second time.
##
## The spans move when a line changes length, so the second save is the one that
## would splice into the wrong place if the file were not read again.
func test_saving_again_after_a_save_changes_nothing() -> void:
	var graph: ComposerGraph = await _open(SOURCE, 8)
	var node: ComposerNode = _applied(graph)
	screen._on_value_edited(node.id, EFFECT, "freezing")
	await wait_frames(2)
	await screen.save()
	var once: String = FileAccess.get_file_as_string(path)

	await screen.save()

	assert_eq(FileAccess.get_file_as_string(path), once, "the same bytes")


func test_saving_without_editing_leaves_the_file_byte_for_byte() -> void:
	await _open(SOURCE, 9)

	var result: ComposerWriter.Result = await screen.save()

	assert_true(result.is_ok(), "saved")
	assert_eq(FileAccess.get_file_as_string(path), SOURCE, "byte for byte")


## A file the Composer cannot draw is never written.
func test_a_read_only_ability_is_not_written() -> void:
	await _open(OUTSIDE, 10)

	var result: ComposerWriter.Result = await screen.save()

	assert_false(result.is_ok(), "refused")
	assert_eq(FileAccess.get_file_as_string(path), OUTSIDE, "and the file is as it was")


## With nothing open there is nothing to save, and it says so rather than
## reaching for a path it does not have.
func test_saving_with_nothing_open_is_refused_by_name() -> void:
	var result: ComposerWriter.Result = await screen.save()

	assert_false(result.is_ok(), "refused")
	assert_true(
		result.refusal.message.contains("no ability"), "%s" % result.refusal.message
	)
#endregion
