## Reading what an enum argument is allowed to hold, and offering it.
##
## Reflection describes an enum parameter as an int with a hint string listing
## its names, and that string is the only place the names exist at runtime. So a
## dropdown here can show the words and must write back the numbers: the enum's
## own identifier is not preserved, and writing `SomeEnum.RUN` would name an
## owner nobody said.
##
## The refusals matter as much as the parsing. A token this cannot read stops the
## whole list, because half a parse is a dropdown missing an option - a value
## somebody can no longer choose and cannot see they have lost.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest


func _field(written: String, hint_string: String) -> ComposerNode.Field:
	return ComposerDeclaredField.of(
		ComposerTypes.INT, written, PROPERTY_HINT_ENUM, hint_string, "Policy"
	)


## What the options come out as, written as `Label=Value`, for a failure to say.
func _read(hint_string: String) -> PackedStringArray:
	var said: PackedStringArray = PackedStringArray()
	for option: ComposerEnumHint.Option in ComposerEnumHint.parse(hint_string):
		said.append("%s=%d" % [option.label, option.value])
	return said


#region What a hint string says
## Every shape of hint the engine writes, and the one answer to a hint that is
## not one.
##
## The mixed row is the rule that is easy to get wrong: after an explicit value,
## the next implicit one carries on from it. That is what GDScript itself does,
## so a dropdown built from this offers the same numbers the language would.
const HINTS: Array = [
	["counted from zero", "Idle,Walk,Run", ["Idle=0", "Walk=1", "Run=2"]],
	["given its own numbers", "Idle:0,Walk:2,Run:7", ["Idle=0", "Walk=2", "Run=7"]],
	[
		"carrying on from the last one given",
		"Idle:0,Walk,Run:5,Jump",
		["Idle=0", "Walk=1", "Run=5", "Jump=6"],
	],
	["counting backwards", "Behind:-2,Level,Ahead:3", ["Behind=-2", "Level=-1", "Ahead=3"]],
	["spaced out", " Idle , Walk : 2 , Run ", ["Idle=0", "Walk=2", "Run=3"]],
	["saying nothing at all", "", []],
	["with an empty name in it", "Idle,,Run", []],
	["with a value that is not a number", "Idle:one,Run", []],
	["with a name that is not a name", "Idle State,Run", []],
]


func test_what_a_hint_string_offers() -> void:
	var checked: int = 0
	for row: Array in HINTS:
		var described: String = row[0]
		var hint_string: String = row[1]
		var expected: Array = row[2]

		assert_eq(
			Array(_read(hint_string)), expected, "%s: `%s`" % [described, hint_string]
		)
		checked += 1
	assert_eq(checked, HINTS.size(), "every shape of hint was read")
#endregion


#region Which fields a dropdown may serve
## What the file holds decides as much as what the engine declared.
##
## The symbol row is the gate: `Policy.INSTANT` is a name this cannot resolve to
## a number, and offering a dropdown for it would rewrite somebody's code into a
## magic number the moment they touched the row.
const SERVED: Array = [
	["a number the hint lists", "2", "Idle,Walk,Run", true],
	["the first one", "0", "Idle,Walk,Run", true],
	["a number the hint does not list", "9", "Idle,Walk,Run", false],
	["a symbol", "Policy.INSTANT", "Idle,Walk,Run", false],
	["an expression", "1 + 1", "Idle,Walk,Run", false],
	["a number with no hint to check it against", "1", "", false],
]


func test_which_values_a_dropdown_may_be_offered_for() -> void:
	var checked: int = 0
	for row: Array in SERVED:
		var described: String = row[0]
		var written: String = row[1]
		var hint_string: String = row[2]
		var served: bool = row[3]

		var field: ComposerNode.Field = _field(written, hint_string)

		assert_eq(ComposerEnumHint.supports(field), served, "%s: `%s`" % [described, written])
		assert_eq(
			ComposerValueShape.of(field) == ComposerValueShape.Kind.ENUM,
			served,
			"%s: and the row is shaped to match" % described
		)
		checked += 1
	assert_eq(checked, SERVED.size(), "every kind of value was offered")


## An int that is not an enum is still a number.
func test_a_plain_int_is_not_a_dropdown() -> void:
	var field: ComposerNode.Field = _field("3", "")
	field.hint = PROPERTY_HINT_NONE

	assert_false(ComposerEnumHint.supports(field), "nothing said it was an enum")
	assert_eq(
		ComposerValueShape.of(field), ComposerValueShape.Kind.NUMBER, "so it counts"
	)
#endregion


#region What the row does with one
## The dropdown offers the names and writes back the number.
func test_the_row_offers_the_names_and_writes_the_number() -> void:
	var editor: ComposerValueEditor = ComposerValueEditor.new()
	add_child_autofree(editor)

	editor.configure(_field("2", "Idle,Walk,Run"))
	await get_tree().process_frame

	var chosen: Array[Node] = editor.find_children("", "OptionButton", true, false)
	assert_eq(chosen.size(), 1, "one dropdown")
	var button: OptionButton = chosen[0]
	assert_eq(button.item_count, 3, "with a name for each option")
	assert_eq(button.get_item_text(2), "Run", "read the way the engine wrote them")
	assert_eq(button.selected, 2, "and the one the file holds is the one picked")
	assert_eq(editor.source_text(), "2", "what it would write is a number")


## Picking another option writes that option's own number, not its place.
func test_picking_an_option_writes_the_number_it_stands_for() -> void:
	var editor: ComposerValueEditor = ComposerValueEditor.new()
	add_child_autofree(editor)
	editor.configure(_field("0", "Idle:0,Walk:2,Run:7"))
	await get_tree().process_frame
	watch_signals(editor)

	var button: OptionButton = editor.find_children("", "OptionButton", true, false)[0]
	button.selected = 2
	button.item_selected.emit(2)

	assert_eq(editor.source_text(), "7", "the number that option stands for")
	assert_signal_emitted_with_parameters(editor, "committed", ["7"], 0)


## Escape puts the dropdown back, not a text box.
##
## The row used to remember four parts of a field, so pressing Escape on a
## dropdown or a resource picker handed back a plain line to type into - and the
## control a person had was gone until something else redrew the card.
func test_escape_puts_the_same_kind_of_control_back() -> void:
	var editor: ComposerValueEditor = ComposerValueEditor.new()
	add_child_autofree(editor)
	editor.configure(_field("1", "Idle,Walk,Run"))
	await get_tree().process_frame

	editor.reset_to("1")
	await get_tree().process_frame

	assert_eq(
		editor.find_children("", "OptionButton", true, false).size(),
		1,
		"still a dropdown"
	)
	assert_eq(editor.source_text(), "1", "holding what it was put back to")
#endregion
