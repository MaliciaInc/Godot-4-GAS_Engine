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
## @meta_license: GAS_Engine Community Use License 1.0
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

## Two locals of the same type, so one cable has somewhere else to go.
## Two locals, each read twice over, and the first statement is the one edited.
##
## The spare readers are not decoration. Rewiring an argument away from a local
## takes a reader off it, and a local nothing reads any more is a warning in the
## file the Composer just wrote - which would fail this test for a reason that
## has nothing to do with cables. Every local here keeps a reader in both
## states, so what is left to observe is only the cable moving.
const REWIRE: String = """extends GameplayAbility

@export var burning: GameplayEffect


func _activate_ability() -> bool:
	var level: float = get_ability_level()
	var louder: float = get_ability_level()
	owner_asc.apply_gameplay_effect(burning, owner_asc, level)
	owner_asc.apply_gameplay_effect(burning, owner_asc, level)
	owner_asc.apply_gameplay_effect(burning, owner_asc, louder)
	end_ability()
	return true
"""

## Two statements in an order nothing forces, so swapping them is a reorder
## rather than a file that stopped compiling.
const ORDERED: String = """extends GameplayAbility


func _activate_ability() -> bool:
	owner_asc.add_tag(&"One")
	owner_asc.add_tag(&"Two")
	end_ability()
	return true
"""

const FIRST_TAG: String = "&\"One\""
const SECOND_TAG: String = "&\"Two\""

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
	for node: ComposerNode in ComposerProjection.statements(graph):
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


## A value fed by a cable is offered as a choice, not as a box.
##
## It was refused outright for a while, on the grounds that a cable cannot be
## typed over. That was wrong: the text is the truth here and the cable is read
## out of it, so naming a different local rewires and writing a literal
## disconnects. What changes for a wired value is what it is offered as.
func test_a_value_that_arrives_on_a_cable_is_offered_as_what_feeds_it() -> void:
	var graph: ComposerGraph = await _open(SOURCE, 2)
	var node: ComposerNode = _applied(graph)

	assert_eq(node.fields[LEVEL].source, ComposerNode.ValueSource.WIRED, "it is wired")
	assert_true(node.may_edit(node.fields[LEVEL]), "and it can still be changed")
	assert_false(node.may_type(node.fields[LEVEL]), "but not by typing over it")
	assert_true(node.may_type(node.fields[SOURCE_ASC]), "while the one beside it is typed")


## Rewiring: the argument names a different local, and the cable follows.
func test_naming_another_local_moves_the_cable() -> void:
	var graph: ComposerGraph = await _open(REWIRE, 20)
	var node: ComposerNode = _applied(graph)

	var reachable: Array[ComposerNode.Port] = graph.locals_reaching(
		node, node.fields[LEVEL].type_name
	)
	var names: PackedStringArray = PackedStringArray()
	for port: ComposerNode.Port in reachable:
		names.append(port.label)
	assert_true(names.has("louder"), "the other local fits too: %s" % [names])

	screen._on_value_edited(node.id, LEVEL, "louder")
	await wait_frames(2)

	var after: ComposerNode = _applied(screen.graph())
	assert_eq(after.fields[LEVEL].display, "louder", "the argument names the other one")
	assert_eq(after.fields[LEVEL].source, ComposerNode.ValueSource.WIRED, "still fed")


## Disconnecting: a literal where a name was, and the cable is gone.
func test_writing_a_value_takes_the_cable_off() -> void:
	var graph: ComposerGraph = await _open(REWIRE, 21)
	var node: ComposerNode = _applied(graph)

	screen._on_value_edited(node.id, LEVEL, "3.0")
	await wait_frames(2)

	var after: ComposerNode = _applied(screen.graph())
	assert_eq(after.fields[LEVEL].display, "3.0", "a written value")
	assert_eq(after.fields[LEVEL].source, ComposerNode.ValueSource.LITERAL, "not fed")


## A structural statement offers the one value it carries, and nothing else.
##
## This used to assert the opposite, because the writer could only rebuild a
## call - which left every condition and every return value on the canvas and
## out of reach. What is still true is the narrower thing: a statement that
## hands nothing back has nothing to offer.
func test_a_structural_statement_offers_exactly_the_value_it_carries() -> void:
	var graph: ComposerGraph = await _open(SOURCE, 3)
	var structural: int = 0

	for node: ComposerNode in ComposerProjection.statements(graph):
		if not node.type_id.is_empty():
			continue
		structural += 1
		assert_eq(node.fields.size(), 1, "%s carries one value" % node.title)
		assert_true(node.may_edit(node.fields[0]), "%s offers it" % node.title)
	assert_gt(structural, 0, "the body has at least one of them")

	var bare: ComposerGraph = ComposerReader.read(
		"extends GameplayAbility


func _activate_ability() -> void:
	return
", path
	)
	var end: ComposerNode = ComposerProjection.statements(bare)[0]
	assert_eq(end.fields.size(), 0, "a bare return hands nothing back")


## A file outside the subset opens read-only, and nothing in it is offered.
func test_nothing_is_offered_in_a_file_the_composer_cannot_draw() -> void:
	var graph: ComposerGraph = await _open(OUTSIDE, 4)

	assert_false(graph.is_editable(), "read-only: %s" % graph.blocked_reason())
	assert_eq(ComposerProjection.statements(graph).size(), 0, "and there is nothing on the canvas to offer")
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
	[SOURCE_ASC, "caster", true, "another value somebody wrote"],
]


func test_only_the_values_that_can_be_typed_are_changed() -> void:
	await _open(SOURCE, 5)

	for row: Array in EDITS:
		# Fetched inside the loop: an edit replaces the graph, and the node held
		# from before it is an ability that is no longer open.
		var node: ComposerNode = _applied(screen.graph())
		var position: int = row[0]
		var written: String = row[1]
		var takes: bool = row[2]
		var described: String = row[3]
		var before: String = node.fields[position].display
		node.dirty = false

		screen._on_value_edited(node.id, position, written)
		await wait_frames(2)

		var after: ComposerNode = _applied(screen.graph())
		assert_eq(
			after.fields[position].display, written if takes else before,
			"%s: %s" % [described, "changes" if takes else "is left alone"]
		)


## A missing argument that is filled in stops being missing.
##
## The gap is the validator's doing, not the statement's. Typing into it has to
## turn it into a real argument, or the next pass strips it back out and the
## person watches what they wrote disappear.
func test_filling_in_a_missing_argument_keeps_what_was_typed() -> void:
	await screen.open(SHORT, AN_ABILITY)
	var graph: ComposerGraph = screen.graph()
	var node: ComposerNode = ComposerProjection.statements(graph)[0]

	assert_eq(node.fields[EFFECT].source, ComposerNode.ValueSource.MISSING, "a gap")
	assert_eq(graph.diagnostics.size(), 1, "and the panel says so")

	screen._on_value_edited(node.id, EFFECT, "state_burning")
	await wait_frames(2)

	# Read again: an edit replaces the graph, so the one held before it is an
	# ability that is no longer open.
	var after: ComposerNode = ComposerProjection.statements(screen.graph())[0]
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


#region Reordering
## A document over a real file, without going through a screen: reordering is a
## source edit and has nothing to draw.
func _document(source: String, tag: int) -> ComposerDocument:
	path = SCRATCH % tag
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	out.store_string(source)
	out.close()

	var doc: ComposerDocument = ComposerDocument.new()
	doc.open(source, path)
	return doc


## Which of the two tags is written first, as the file stands.
func _first_written(doc: ComposerDocument) -> String:
	var printed: String = doc.printed()
	return FIRST_TAG if printed.find(FIRST_TAG) < printed.find(SECOND_TAG) else SECOND_TAG


func _spans(doc: ComposerDocument) -> Array[ComposerSpan]:
	var found: Array[ComposerSpan] = []
	for node: ComposerNode in ComposerProjection.statements(doc.graph()):
		found.append(node.span)
	return found


## Dragging a card no longer reorders anything, but reordering is still a thing
## somebody can ask for, and it still goes through the door that reads the file
## back before accepting it.
func test_moving_a_statement_puts_it_where_the_other_one_was() -> void:
	var doc: ComposerDocument = _document(ORDERED, 20)
	var spans: Array[ComposerSpan] = _spans(doc)
	assert_gt(spans.size(), 1, "there are statements to reorder")
	assert_eq(_first_written(doc), FIRST_TAG, "One is written first to begin with")

	assert_null(doc.move(spans[1], spans[0]), "the move was taken")

	assert_eq(_first_written(doc), SECOND_TAG, "and Two is written first now")
	assert_eq(_spans(doc).size(), spans.size(), "with nothing lost on the way")


## A statement moved onto itself is not a move, and must not become an undo step
## somebody has to press past.
func test_moving_a_statement_onto_itself_changes_nothing() -> void:
	var doc: ComposerDocument = _document(ORDERED, 21)
	var spans: Array[ComposerSpan] = _spans(doc)
	var before: String = doc.printed()

	doc.move(spans[0], spans[0])

	assert_eq(doc.printed(), before, "the file is the file it was")


## The text is the whole state, so taking a reorder back is putting it back.
func test_a_reorder_can_be_taken_back() -> void:
	var doc: ComposerDocument = _document(ORDERED, 22)
	var spans: Array[ComposerSpan] = _spans(doc)
	var before: String = doc.printed()

	assert_null(doc.move(spans[1], spans[0]), "the move was taken")
	assert_ne(doc.printed(), before, "and it changed the file")
	doc.undo()

	assert_eq(doc.printed(), before, "back byte for byte")


## A span nothing was read from moves nothing. The reorder arrives from a canvas
## that was drawn a moment ago, and a card that is no longer there must not turn
## into a statement landing somewhere arbitrary.
func test_a_span_that_points_at_nothing_moves_nothing() -> void:
	var doc: ComposerDocument = _document(ORDERED, 23)
	var spans: Array[ComposerSpan] = _spans(doc)
	var before: String = doc.printed()

	doc.move(ComposerSpan.new(), spans[0])
	assert_eq(doc.printed(), before, "an unread statement moves nothing")

	doc.move(spans[0], ComposerSpan.new())
	assert_eq(doc.printed(), before, "and neither does an unread target")
#endregion
