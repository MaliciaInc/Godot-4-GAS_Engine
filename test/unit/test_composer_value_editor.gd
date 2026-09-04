## What a field is edited with, and what comes back out of it.
##
## The property that matters is the round trip: what the file says goes into a
## control, and what the control says goes back as GDScript that means the same
## thing. A control that shows `1.0` and hands back `1` has quietly changed an
## argument's type; one that shows `fire` and hands back `fire` without the
## marks has written a String where a StringName was declared.
##
## The second property is that a control is only offered where it can tell the
## truth. An argument holding an expression gets a plain line, because a spinner
## over `pick.strength` cannot show what is there and destroys it the moment it
## is touched.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const WIRED: ComposerNode.ValueSource = ComposerNode.ValueSource.WIRED


func _field(
	type_name: StringName, written: String, hint_string: String = ""
) -> ComposerNode.Field:
	var made: ComposerNode.Field = ComposerNode.Field.new()
	made.label = "Level"
	made.type_name = type_name
	made.display = written
	made.hint = PROPERTY_HINT_RANGE if not hint_string.is_empty() else PROPERTY_HINT_NONE
	made.hint_string = hint_string
	return made


func _editor(field: ComposerNode.Field, editable: bool = true) -> ComposerValueEditor:
	var made: ComposerValueEditor = ComposerValueEditor.new()
	add_child_autofree(made)
	made.configure(field, editable)
	return made


#region What control a field gets
## Every type that has a control of its own, and the one that does not.
##
## The last row is the whole reason the decision is made from the text and not
## from the type alone: a `float` argument can hold an expression, and it must
## get the same plain line an untyped argument gets.
const SHAPES: Array = [
	[&"bool", "true", ComposerValueShape.Kind.BOOL, "a bool ticks"],
	[&"int", "3", ComposerValueShape.Kind.NUMBER, "an int counts"],
	[&"float", "1.5", ComposerValueShape.Kind.NUMBER, "so does a float"],
	[&"String", "\"burn\"", ComposerValueShape.Kind.TEXT, "text is typed"],
	[&"StringName", "&\"burn\"", ComposerValueShape.Kind.TEXT, "so is a name"],
	[&"NodePath", "^\"a/b\"", ComposerValueShape.Kind.TEXT, "and a path"],
	[&"Vector2", "Vector2(1.0, 2.0)", ComposerValueShape.Kind.VECTOR, "a vector splits"],
	[&"Vector2i", "Vector2i(3, 4)", ComposerValueShape.Kind.VECTOR, "and so does a whole one"],
	[&"Color", "Color(1.0, 0.0, 0.0, 1.0)", ComposerValueShape.Kind.COLOUR, "a colour is picked"],
	[&"float", "pick.strength", ComposerValueShape.Kind.RAW, "an expression is left alone"],
	[&"GameplayEffect", "null", ComposerValueShape.Kind.RESOURCE, "a resource is chosen"],
]


func test_each_kind_of_value_gets_the_control_that_can_show_it() -> void:
	for row: Array in SHAPES:
		var type_name: StringName = row[0]
		var written: String = row[1]
		var wanted: ComposerValueShape.Kind = row[2]
		var described: String = row[3]

		assert_eq(
			ComposerValueShape.of(_field(type_name, written)), wanted, described
		)


## A field fed by a cable is not edited here at all.
##
## Two ways to set one argument is one too many: typing into a wired field would
## silently break the cable somebody can see attached to it.
func test_a_wired_field_gets_no_control_to_type_into() -> void:
	var field: ComposerNode.Field = _field(&"float", "strength")
	field.source = WIRED

	var editor: ComposerValueEditor = _editor(field)

	assert_eq(ComposerValueShape.of(field), ComposerValueShape.Kind.WIRED)
	for child: Node in editor.get_children():
		assert_false(child is LineEdit, "nothing to type into")
		assert_false(child is SpinBox, "and nothing to spin")


## A field shown read-only is shown, not edited, whatever its type would allow.
func test_a_field_opened_read_only_is_only_shown() -> void:
	var editor: ComposerValueEditor = _editor(_field(&"bool", "true"), false)

	for child: Node in editor.get_children():
		assert_false(child is CheckBox, "a look-only file offers nothing to tick")
#endregion


#region What comes back out
## The text a field holds survives being put into a control and read back.
##
## Compared as source rather than as a value, because the source is what is
## written to somebody's file: `1` and `1.0` are the same number and not the
## same argument.
const ROUND_TRIPS: Array = [
	[&"bool", "true", "a bool"],
	[&"bool", "false", "the other bool"],
	[&"int", "7", "a whole number"],
	[&"float", "1.5", "a fractional one"],
	[&"String", "\"burn\"", "a string"],
	[&"StringName", "&\"burn\"", "a name, marks and all"],
	[&"NodePath", "^\"a/b\"", "a path, marks and all"],
	[&"float", "0.125", "a third decimal a coarse step would round away"],
	[&"Vector2", "Vector2(1.0, 2.0)", "a vector"],
	[&"Vector2", "Vector2(0.7071, 0.7071)", "a normalised direction"],
	[&"Vector3", "Vector3(1.0, 2.0, 3.0)", "a longer vector"],
	[&"Vector2i", "Vector2i(3, 4)", "a whole-numbered vector, with no points added"],
	[&"Color", "Color(1.0, 0.0, 0.5, 1.0)", "a colour"],
	[&"Color", "Color(0.1, 0.2, 0.3, 1.0)", "a colour with awkward components"],
	[&"float", "pick.strength", "an expression nobody may touch"],
	[&"GameplayEffect", "null", "an empty resource"],
]


func test_what_goes_in_comes_back_out_unchanged() -> void:
	for row: Array in ROUND_TRIPS:
		var type_name: StringName = row[0]
		var written: String = row[1]
		var described: String = row[2]

		var editor: ComposerValueEditor = _editor(_field(type_name, written))

		assert_eq(editor.source_text(), written, described)


## A name is shown without the marks a person should not have to type, and
## written back with them.
func test_a_name_is_shown_plainly_and_written_back_marked() -> void:
	var editor: ComposerValueEditor = _editor(_field(&"StringName", "&\"burn\""))
	var typed: LineEdit = editor.get_child(0) as LineEdit

	assert_not_null(typed, "a name is typed into a line")
	assert_eq(typed.text, "burn", "shown without its marks")
	assert_eq(editor.source_text(), "&\"burn\"", "and written back with them")


## Typing into a text field writes the marks back around what was typed.
func test_typing_a_name_writes_the_marks_around_it() -> void:
	var editor: ComposerValueEditor = _editor(_field(&"StringName", "&\"burn\""))
	var typed: LineEdit = editor.get_child(0) as LineEdit

	typed.text = "chill"

	assert_eq(editor.source_text(), "&\"chill\"", "the codec spells it, not the control")


## An expression is handed back exactly as it was, edits and all.
func test_an_expression_is_carried_through_untouched() -> void:
	var editor: ComposerValueEditor = _editor(_field(&"float", "pick.strength"))
	var raw: LineEdit = editor.get_child(0) as LineEdit

	assert_eq(raw.text, "pick.strength", "shown whole")
	raw.text = "pick.strength * 2.0"
	assert_eq(editor.source_text(), "pick.strength * 2.0", "and handed back whole")
#endregion


#region Finishing an edit
## Ticking a box is finishing: there is no later moment to wait for.
func test_ticking_a_box_finishes_the_edit() -> void:
	var editor: ComposerValueEditor = _editor(_field(&"bool", "false"))
	watch_signals(editor)
	var box: CheckBox = editor.get_child(0) as CheckBox

	box.button_pressed = true

	assert_signal_emitted(editor, "committed", "the tick is the edit")
	assert_eq(editor.source_text(), "true", "and it says what was ticked")


## Pressing Enter in a line finishes it.
func test_pressing_enter_finishes_a_typed_edit() -> void:
	var editor: ComposerValueEditor = _editor(_field(&"String", "\"burn\""))
	watch_signals(editor)
	var typed: LineEdit = editor.get_child(0) as LineEdit

	typed.text = "chill"
	typed.text_submitted.emit(typed.text)

	assert_signal_emitted(editor, "committed")


## Escape puts back exactly the text this row was configured with.
func test_escaping_restores_the_text_it_was_given() -> void:
	var editor: ComposerValueEditor = _editor(_field(&"String", "\"burn\""))
	var typed: LineEdit = editor.get_child(0) as LineEdit
	typed.text = "chill"
	assert_eq(editor.source_text(), "\"chill\"", "changed")

	editor.reset_to("\"burn\"")

	assert_eq(editor.source_text(), "\"burn\"", "and put back")
#endregion


#region What the engine declared
## A declared range becomes the range of the box, bounds and step alike.
func test_a_declared_range_bounds_the_box() -> void:
	var editor: ComposerValueEditor = _editor(_field(&"float", "1.0", "0,10,0.5"))
	var spin: SpinBox = editor.get_child(0) as SpinBox

	assert_not_null(spin, "a number is spun")
	assert_eq(spin.min_value, 0.0, "the declared floor")
	assert_eq(spin.max_value, 10.0, "the declared ceiling")
	assert_eq(spin.step, 0.5, "and the declared step")
	assert_false(spin.allow_greater, "a range without or_greater means the ceiling")


## A range that says the bounds are soft is obeyed on that too.
func test_a_soft_range_lets_the_value_past_its_bounds() -> void:
	var editor: ComposerValueEditor = _editor(
		_field(&"float", "1.0", "0,10,0.5,or_greater")
	)
	var spin: SpinBox = editor.get_child(0) as SpinBox

	assert_true(spin.allow_greater, "the method said so")


## With nothing declared, a number is unbounded and steps by its own kind.
func test_an_undeclared_number_is_unbounded() -> void:
	var whole: SpinBox = _editor(_field(&"int", "3")).get_child(0) as SpinBox
	var fractional: SpinBox = _editor(_field(&"float", "3.0")).get_child(0) as SpinBox

	assert_true(whole.rounded, "an int has no fraction to show")
	assert_eq(whole.step, ComposerValueEditor.INT_STEP, "and counts by one")
	assert_false(fractional.rounded, "a float does")
	assert_true(whole.allow_greater, "and neither is capped by an undeclared bound")
#endregion


#region Finishing without changing
## A finish that changed nothing says nothing.
##
## Focus leaves a control every time somebody clicks past it, and every commit
## carries an undo. Without this, tabbing through an ability marks every
## statement it passes as edited and fills the history with changes nobody made.
func test_leaving_a_control_untouched_commits_nothing() -> void:
	var editor: ComposerValueEditor = _editor(_field(&"String", "\"burn\""))
	watch_signals(editor)
	var typed: LineEdit = editor.get_child(0) as LineEdit

	typed.focus_exited.emit()

	assert_signal_not_emitted(editor, "committed", "nothing changed, so nothing happened")


## The same control, actually changed, does say so.
func test_leaving_a_control_that_changed_commits_once() -> void:
	var editor: ComposerValueEditor = _editor(_field(&"String", "\"burn\""))
	watch_signals(editor)
	var typed: LineEdit = editor.get_child(0) as LineEdit

	typed.text = "chill"
	typed.focus_exited.emit()
	typed.focus_exited.emit()

	assert_signal_emit_count(
		editor, "committed", 1, "once for the change, and not again for leaving twice"
	)


## Configuring a row leaves exactly one control in it.
##
## `queue_free` happens at the end of the frame, so children only queued are
## still children: still laid out, still reachable by index, still able to emit.
## This row is read by index in the same frame it is configured.
func test_configuring_a_row_twice_leaves_one_control() -> void:
	var editor: ComposerValueEditor = _editor(_field(&"String", "\"burn\""))

	editor.configure(_field(&"bool", "true"))

	assert_eq(editor.get_child_count(), 1, "one control, not two")
	assert_true(editor.get_child(0) is CheckBox, "and it is the new one")
	assert_eq(editor.source_text(), "true", "which is what the row now means")
#endregion
