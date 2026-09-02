## Adding a statement, taking one out, and putting the file back.
##
## Every one of these is a change to the **text**. The graph is read again
## afterwards, so nothing can end up describing an ability the file does not
## say - and undo is the string from before, which puts back the nodes, the
## cables, the marks and the layout together because all of them were worked out
## from it in the first place.
##
## The claim worth holding onto: an edit that would leave a file the Composer
## cannot read is refused before it happens, not discovered afterwards. Blanking
## somebody's canvas and then explaining why is not a recovery.
##
## @meta_license: MIT
extends GutTest

const SOURCE: String = """extends GameplayAbility

@export var burning: GameplayEffect


func _activate_ability() -> bool:
	commit_ability()

	# The one with a note above it.
	owner_asc.apply_gameplay_effect(burning, owner_asc)
	end_ability()
	return true
"""

const SCRATCH: String = "user://composer_commands_%d.gd"

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


func _open(tag: int, source: String = SOURCE) -> void:
	path = SCRATCH % tag
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	out.store_string(source)
	out.close()
	await screen.open(source, path)


func _pick(title: String) -> void:
	for node: ComposerNode in screen.graph().nodes:
		if node.title == title:
			screen.canvas().reveal(node.id)
			return


func _titles() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for node: ComposerNode in screen.graph().nodes:
		found.append(node.title)
	return found


#region Taking one out
func test_removing_a_statement_takes_its_comment_with_it() -> void:
	await _open(1)
	_pick("Apply Gameplay Effect")

	assert_true(await screen.remove_picked(), "removed")

	assert_false(_titles().has("Apply Gameplay Effect"), "the statement is gone")
	assert_false(
		screen.printed().contains("# The one with a note above it."),
		"and so is the note that belonged to it"
	)
	assert_true(screen.printed().contains("end_ability()"), "the rest is where it was")


## Removing everything still leaves a body, or the file stops parsing.
##
## A tool that breaks somebody's script by deleting the last node is not one
## they open a second time.
func test_removing_every_statement_leaves_a_body_behind() -> void:
	await _open(2)
	screen.canvas()._pick(_all_ids())

	assert_true(await screen.remove_picked(), "removed")

	assert_true(screen.printed().contains("pass"), "the body says it does nothing")
	assert_true(screen.graph().is_editable(), "and it still reads: %s" % screen.printed())


func _all_ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for node: ComposerNode in screen.graph().nodes:
		found.append(node.id)
	return found
#endregion


#region Putting one in
## A node picked out of the palette is written on the thing it is a method of.
##
## Which receiver a call needs is a fact about the file it is going into, and
## there are three answers: nothing at all for one of the ability's own methods,
## a property for one on the ability system, and the class for a static call.
## Written on the wrong thing - or bare when it needs one - the line does not
## compile, and the tool put it there rather than the person.
const PLACED: Array[Array] = [
	[
		ComposerCatalog.ASC_CLASS, &"add_tag", "	owner_asc.add_tag()",
		"on the ability system, through the property that holds one",
	],
	[
		ComposerCatalog.ABILITY_CLASS, &"abort_ability", "	abort_ability()",
		"bare, because the file already is an ability",
	],
	[
		ComposerCatalog.ABILITY_CLASS, &"wait_target_data",
		"	await wait_target_data()", "with the word that makes it wait",
	],
]


func test_a_node_from_the_palette_is_written_the_way_it_has_to_be_called() -> void:
	await _open(3)

	for row: Array in PLACED:
		var declared: StringName = row[0]
		var method: StringName = row[1]
		var expected: String = row[2]
		var described: String = row[3]

		screen._on_node_picked(
			ComposerCatalog.key_for(ComposerCatalog.script_for(declared), method)
		)
		await wait_frames(2)

		assert_true(
			screen.printed().contains(expected), "%s: %s" % [described, screen.printed()]
		)


func test_repeating_a_statement_writes_it_twice() -> void:
	await _open(6)
	_pick("Commit Ability")

	assert_true(await screen.repeat_picked(), "repeated")

	var seen: int = 0
	for title: String in _titles():
		if title == "Commit Ability":
			seen += 1
	assert_eq(seen, 2, "twice on the canvas")
#endregion


#region Going back
## Undo puts the text back, and everything is read out of it again.
func test_undo_puts_the_file_back_exactly() -> void:
	await _open(7)
	var before: String = screen.printed()
	_pick("Commit Ability")
	await screen.remove_picked()

	await screen.undo()

	assert_eq(screen.printed(), before, "byte for byte")
	assert_true(_titles().has("Commit Ability"), "and the node is back on the canvas")


func test_redo_puts_the_change_back() -> void:
	await _open(8)
	_pick("Commit Ability")
	await screen.remove_picked()
	var edited: String = screen.printed()
	await screen.undo()

	await screen.redo()

	assert_eq(screen.printed(), edited, "back where it was")


## Editing after undoing drops what was undone.
##
## The branch somebody undid is not where they are any more, and offering to
## redo into it would take them somewhere they never were.
func test_editing_after_an_undo_drops_the_way_forward() -> void:
	await _open(9)
	_pick("Commit Ability")
	await screen.remove_picked()
	await screen.undo()

	_pick("End Ability")
	await screen.remove_picked()

	assert_false(screen.history().can_redo(), "there is no forward any more")


func test_there_is_nothing_to_undo_in_a_file_nobody_has_touched() -> void:
	await _open(10)

	assert_false(screen.history().can_undo(), "nothing done yet")
	await screen.undo()
	assert_eq(screen.printed(), SOURCE, "and asking anyway changed nothing")
#endregion


#region Refusing rather than breaking
## Text that does not belong in a body is refused before it is accepted.
##
## The canvas would otherwise go blank and the person would be left holding a
## file they can no longer see, which is not something an explanation fixes.
func test_a_paste_that_would_break_the_file_is_refused() -> void:
	await _open(11)
	var before: String = screen.printed()
	DisplayServer.clipboard_set("\tfor step: int in 3:\n\t\tend_ability()")

	var took: bool = await screen.paste_text(
		"	for step: int in 3:
		end_ability()"
	)

	assert_false(took, "refused")
	assert_push_error(ComposerDocument.BROKE_IT)
	assert_eq(screen.printed(), before, "and the file is where it was")


func test_copying_puts_the_statement_on_the_clipboard_as_gdscript() -> void:
	await _open(12)
	_pick("Commit Ability")

	assert_eq(
		screen.copy_picked().strip_edges(), "commit_ability()",
		"the line, as a person would paste it into the script editor"
	)


func test_pasting_a_statement_puts_it_in() -> void:
	await _open(13)
	DisplayServer.clipboard_set("\tabort_ability()")

	assert_true(await screen.paste_text("	abort_ability()"), "pasted")

	assert_true(_titles().has("Abort Ability"), "and it is on the canvas")
#endregion


#region Dragging one onto another
## Dragging a card means moving its statement.
##
## Cards have no positions of their own: the layout works out where each goes
## from the order the statements run in. So the only honest thing a drag can do
## is put the statement somewhere, and the card follows because the layout is
## asked again. Anything else would need a position stored beside the file - the
## parallel truth this whole tool exists without.
func test_dragging_a_card_onto_another_moves_its_statement() -> void:
	await _open(14)
	var titles: PackedStringArray = _titles()
	var last: StringName = screen.graph().nodes[screen.graph().nodes.size() - 1].id
	var first: StringName = screen.graph().nodes[0].id

	screen._on_node_dropped(last, first)
	await wait_frames(2)

	assert_ne(_titles(), titles, "the order changed")
	assert_eq(_titles()[0], titles[titles.size() - 1], "the dragged one is where it landed")
	assert_eq(_titles().size(), titles.size(), "and nothing was lost on the way")


## Moving one and putting it back leaves the file exactly as it was.
func test_a_move_and_an_undo_leave_the_file_untouched() -> void:
	await _open(15)
	var before: String = screen.printed()
	var nodes: Array[ComposerNode] = screen.graph().nodes

	screen._on_node_dropped(nodes[nodes.size() - 1].id, nodes[0].id)
	await wait_frames(2)
	await screen.undo()

	assert_eq(screen.printed(), before, "byte for byte")


## A card dropped on itself is not a move.
func test_dropping_a_card_on_itself_changes_nothing() -> void:
	await _open(16)
	var before: String = screen.printed()
	var only: StringName = screen.graph().nodes[0].id

	screen._on_node_dropped(only, only)
	await wait_frames(2)

	assert_eq(screen.printed(), before, "nothing happened")
	assert_false(screen.history().can_undo(), "and nothing was recorded as having")
#endregion
