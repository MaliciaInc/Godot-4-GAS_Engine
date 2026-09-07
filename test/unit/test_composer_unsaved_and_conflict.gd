## Losing somebody's work, in the three ways the Composer could.
##
## It could overwrite an edit made outside it: the save wrote whatever was in
## memory over whatever was on disk, so an ability changed in the script editor
## - or by a merge, or by a teammate - was gone the next time the Composer
## saved. It now refuses when the file no longer reads as the text it was
## opened with, and says so.
##
## It could lose the file itself: writing in place leaves a window in which the
## ability is neither the old text nor the new one, and a crash or a full disk
## in that window leaves nothing. The replacement is written beside it and only
## swapped in once what is on disk reads back as what was asked for.
##
## And it could drop the edits somebody had not saved yet, by opening another
## ability over them without a word. There is a dirty flag now, and it is
## computed rather than remembered: an undo back to where the file started is
## not an unsaved change, and a flag each edit set would have said it was.
##
## The plugin-level half of that last one - the Save/Discard/Cancel dialog and
## the recovery copy an editor teardown writes - is asked for here as far as a
## suite with no editor can reach: the dialog's three answers, the recovery
## file, and the document's side of each choice.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Plugin = preload("res://addons/GAS_Engine/gas_engine_plugin.gd")
const PluginWiring = preload("res://test/fixtures/plugin_wiring.gd")

const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"
const BODY: String = "\tcommit_ability()\n\treturn true\n"
const OTHER_BODY: String = "\tend_ability()\n\treturn true\n"

## A real file, under a directory this suite is allowed to write in.
const SCRATCH: String = "user://gas_engine_test/unsaved"

var doc: ComposerDocument = null
var path: String = ""


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH))
	path = "%s/ability_%d.gd" % [SCRATCH, randi()]
	_write(HEAD + BODY)
	doc = ComposerDocument.new()
	doc.open(HEAD + BODY, path)


func after_each() -> void:
	for suffix: String in ["", ".gas_engine.tmp", ".gas_engine.bak"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	doc = null
	path = ""


#region Getting there
func _write(content: String) -> void:
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	out.store_string(content)
	out.close()


func _on_disk() -> String:
	var read: FileAccess = FileAccess.open(path, FileAccess.READ)
	if read == null:
		return ""
	var text: String = read.get_as_text()
	read.close()
	return text


## An edit that really changes the file: one more statement.
func _edit() -> void:
	var refusal: ComposerGraph.Diagnostic = doc.commit(
		HEAD + "\tend_ability()\n" + BODY
	)
	assert_null(refusal, "the edit was accepted")
#endregion


#region Whether anything is unsaved
## Editing makes it dirty, saving makes it clean, and undo makes it clean again.
##
## The undo row is the one a remembered flag gets wrong. Coming back to the text
## the file was opened with is not an unsaved change, however many steps it took
## to get there, and a tool that asked anyway would train somebody to dismiss
## the question.
func test_dirty_follows_the_text_and_not_the_number_of_edits() -> void:
	assert_false(doc.is_dirty(), "a file just opened has nothing unsaved")

	_edit()
	assert_true(doc.is_dirty(), "and an edit is something unsaved")

	doc.undo()
	assert_false(doc.is_dirty(), "undone back to where it started, nothing is")

	doc.redo()
	assert_true(doc.is_dirty(), "and forward again, something is")

	assert_null(doc.save(), "the save went through")
	assert_false(doc.is_dirty(), "so there is nothing unsaved now")


## Discarding puts the file back and leaves nothing to undo into.
##
## The history has to go with it: what it held were steps back through edits
## that no longer exist, and an undo into them would put back text nobody can
## reach from the file any more.
func test_discarding_returns_to_the_opened_text_and_forgets_the_way_back() -> void:
	_edit()
	_edit()

	doc.discard_unsaved_changes()

	assert_eq(doc.printed(), HEAD + BODY, "back to what was opened")
	assert_false(doc.is_dirty(), "with nothing unsaved")
	assert_false(doc.history().can_undo(), "and nowhere to undo into")


## An edit that is saved leaves the history alone.
##
## Saving is not discarding: somebody who saves halfway through a session still
## expects Ctrl-Z to work.
func test_saving_keeps_the_history() -> void:
	_edit()
	assert_true(doc.history().can_undo(), "there is a step back")

	assert_null(doc.save(), "the save went through")

	assert_true(doc.history().can_undo(), "and there still is")
#endregion


#region What is on disk
## A file changed outside the Composer is not overwritten.
##
## B12. The save wrote memory over disk without looking, so an edit made in the
## script editor was gone the next time somebody pressed save here. Asked for
## both states of the document, because a clean one is the case where nothing
## warns anybody: there is no unsaved work to prompt about and the overwrite is
## silent.
##
##     [what the document is, whether to edit it first]
const WHEN_DISK_MOVED: Array = [
	["a document with nothing unsaved", false],
	["a document with unsaved changes", true],
]


func test_a_file_changed_outside_the_composer_is_never_overwritten() -> void:
	var checked: int = 0
	for row: Array in WHEN_DISK_MOVED:
		var described: String = row[0]
		var edit_first: bool = row[1]

		before_each()
		if edit_first:
			_edit()
		var theirs: String = HEAD + OTHER_BODY
		_write(theirs)

		var refusal: ComposerGraph.Diagnostic = doc.save()

		assert_not_null(refusal, "%s: the save was refused" % described)
		assert_true(
			refusal.message.contains("changed on disk"),
			"%s: and says why: %s" % [described, refusal.message if refusal != null else ""]
		)
		assert_eq(_on_disk(), theirs, "%s: the other edit is still there" % described)
		checked += 1
	assert_eq(checked, WHEN_DISK_MOVED.size(), "both states were asked")


## A file that is gone is not recreated by a save.
##
## Somebody deleted or moved the ability. Writing it back would resurrect a file
## they meant to be rid of, under a path that may now mean something else.
func test_a_file_that_is_gone_is_not_written_back() -> void:
	_edit()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var refusal: ComposerGraph.Diagnostic = doc.save()

	assert_not_null(refusal, "the save was refused")
	assert_false(FileAccess.file_exists(path), "and nothing was recreated")


## A replacement that cannot be finished leaves the original readable.
##
## The window this closes is the one where the file is neither text: writing in
## place empties it first, so a crash there leaves an ability that is gone.
##
## Provoked where the transaction really can fail - the temporary copy cannot be
## opened, because something else is already sitting at that name - and what has
## to survive is the original, untouched and still readable.
func test_a_replacement_that_cannot_finish_leaves_the_original() -> void:
	var blocked: String = path + ComposerAtomicFile.TMP_SUFFIX
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked))

	var replaced: bool = ComposerAtomicFile.replace(path, HEAD + OTHER_BODY)

	assert_false(replaced, "it could not be replaced")
	assert_eq(_on_disk(), HEAD + BODY, "and the original is exactly as it was")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))


## And a path that is not a file at all is refused before anything moves.
##
## Renaming is indifferent to what it is renaming: handed a directory, the swap
## would put a file in its place and then delete it, with everything under it.
func test_a_path_that_is_not_a_file_is_refused() -> void:
	var directory: String = "%s/not_a_file_%d.gd" % [SCRATCH, randi()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))

	var replaced: bool = ComposerAtomicFile.replace(directory, HEAD + OTHER_BODY)

	assert_false(replaced, "it was refused")
	assert_true(
		DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)),
		"and the directory is still there"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))


## A replacement that finishes leaves no scaffolding behind.
func test_a_replacement_that_finishes_leaves_no_temporary_files() -> void:
	var wanted: String = HEAD + OTHER_BODY

	assert_true(ComposerAtomicFile.replace(path, wanted), "it was replaced")

	assert_eq(_on_disk(), wanted, "with what was asked for")
	assert_false(
		FileAccess.file_exists(path + ComposerAtomicFile.TMP_SUFFIX), "no temporary left"
	)
	assert_false(
		FileAccess.file_exists(path + ComposerAtomicFile.BAK_SUFFIX), "no backup left"
	)
#endregion


#region When there is nowhere left to ask
## The dialog offers three answers, and Cancel is one of them.
##
## A dialog with only the two destructive answers is one somebody dismisses by
## accident and loses their work to, so the third is asserted by name.
func test_the_unsaved_dialog_offers_save_discard_and_cancel() -> void:
	var dialog: ComposerUnsavedDialog = ComposerUnsavedDialog.new()
	add_child_autofree(dialog)
	watch_signals(dialog)

	assert_eq(dialog.ok_button_text, "Save", "the confirming answer is Save")
	assert_not_null(dialog.get_cancel_button(), "there is a way out")

	dialog._on_discard()
	assert_signal_emitted(dialog, "discard_chosen", "and Discard says so")


## An editor going away with unsaved work writes it somewhere findable.
##
## Not a substitute for the dialog: this is the case where there is nobody left
## to ask, because the plugin is leaving the tree and cannot hold a modal open.
## Losing the work silently is the one outcome that must not happen.
func test_unsaved_work_is_written_somewhere_when_there_is_no_one_to_ask() -> void:
	var unsaved: String = HEAD + OTHER_BODY

	var written: String = ComposerRecovery.write("res://abilities/fireball.gd", unsaved)

	assert_false(written.is_empty(), "a copy was written")
	var read: FileAccess = FileAccess.open(written, FileAccess.READ)
	assert_not_null(read, "and it can be opened")
	assert_eq(read.get_as_text(), unsaved, "holding what was unsaved")
	read.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(written))


## The copy is named after where the ability came from.
##
## Somebody looking for their work has the path they lost it from and nothing
## else, so that is what the name has to be built out of - and it has to survive
## being a filename, which a path with slashes in it does not.
func test_the_recovery_copy_is_named_after_the_ability_it_came_from() -> void:
	var written: String = ComposerRecovery.write("res://abilities/fire/ball.gd", HEAD)

	assert_false(written.is_empty(), "a copy was written")
	assert_true(
		written.get_file().begins_with("abilities__fire__ball.gd"),
		"named after the path it came from: %s" % written
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(written))
#endregion


#region Opening another ability over unsaved work
## The plugin's own navigation, asked of its source.
##
## Godot refuses outright: `Class 'EditorPlugin' can only be instantiated by
## editor`. So the behaviour cannot be driven from a suite that has no editor,
## and every piece the navigation is built out of is covered above instead - the
## dialog's three answers, the document's side of save, discard and dirty, and
## the recovery copy.
##
## What is left is the wiring between them, and the wiring is the part that lost
## somebody's work: opening used to replace the open document outright. A
## source-level assertion is weaker than running it, and it is not nothing -
## disconnect any one of these and this fails, which is the regression that
## actually happened.
##
## The manual case remains: open an ability, edit it, open another, and answer
## the question three times.
## What the navigation is made of, and why each line has to be there.
const WIRED: Array = [
	[
		"opening asks before replacing",
		"_composer_instance.has_unsaved_changes()",
	],
	["and remembers what was asked for", "_pending_composer_open_path = source_path"],
	["Save is answered", "_composer_unsaved_dialog.save_chosen.connect(_accept_pending_after_save)"],
	[
		"Discard is answered",
		"_composer_unsaved_dialog.discard_chosen.connect(_accept_pending_after_discard)",
	],
	["Cancel is answered", "_composer_unsaved_dialog.cancel_chosen.connect(_cancel_pending_open)"],
	["Cancel opens nothing", "func _cancel_pending_open() -> void:"],
	["and leaving the tree keeps the work", "ComposerRecovery.write("],
]


func test_the_plugin_wires_every_answer_to_the_unsaved_question() -> void:
	assert_eq(
		PluginWiring.missing(WIRED), [] as Array[String], "every answer is wired"
	)
#endregion
