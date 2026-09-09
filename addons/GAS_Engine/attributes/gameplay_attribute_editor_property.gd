## Picking an attribute instead of typing one.
##
## A dropdown of everything the project declares, written as
## `<set>.<attribute>`, which is what a person recognises and what tells two
## `health` attributes apart. What it writes is a `GameplayAttributeRef` - the
## typed reference the runtime resolves - rather than a bare name that only
## turns out to be wrong while somebody is playing.
##
## A value the project does not declare is kept, shown, and coloured in the
## host editor's own error colour. Never
## cleared: an editor that quietly deleted a name because it could not find it
## would be an editor that loses work whenever a set is renamed, and the author
## would not know until the effect stopped doing anything.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name GameplayAttributeEditorProperty extends EditorProperty

## The theme entry a Control's own text colour is called, and the colour an
## unknown value is shown in.
##
## A named engine colour rather than the host editor's `error_color`, which
## would read better against a light theme and would mean this file naming a
## class under `editor/`. Nothing outside that folder does, so a running game
## has no path by which it loads any of it - and this file, editor-only as it
## is, sits under `attributes/` where the phase document puts it.
const FONT_COLOR: String = "font_color"
const WRONG: Color = Color.RED

## What the dropdown says when nothing is chosen, and what it says about a
## choice the project does not have.
const NOTHING_CHOSEN: String = "<no attribute>"
const UNKNOWN: String = "%s — not declared by any attribute set"


var _choices: OptionButton = null

## What each dropdown index stands for. Index zero is always "nothing chosen",
## so the entries start at one.
var _entries: Array[GameplayAttributeCatalog.Entry] = []

## The unknown value being shown, when there is one. Kept so refreshing the
## dropdown does not lose it.
var _unknown: GameplayAttributeRef = null


func _init() -> void:
	_choices = OptionButton.new()
	_choices.item_selected.connect(_on_chosen)
	add_child(_choices)
	add_focusable(_choices)


## Fill the dropdown and select what the property currently holds.
func _update_property() -> void:
	var held: GameplayAttributeRef = get_edited_object().get(get_edited_property())
	_rebuild(held)


## Whether what is held is something the project actually declares.
##
## The rule itself is GameplayAttributeCatalog.is_unknown, because Godot
## refuses to build an EditorProperty outside the editor and a rule living
## here would be a rule nothing can check. This only reports what was shown.
func shows_an_unknown_attribute() -> bool:
	return _unknown != null


func _rebuild(held: GameplayAttributeRef) -> void:
	_choices.clear()
	_entries.clear()
	_unknown = null

	_choices.add_item(NOTHING_CHOSEN)
	var chosen: int = 0
	for entry: GameplayAttributeCatalog.Entry in GameplayAttributeCatalog.entries():
		_entries.append(entry)
		_choices.add_item(entry.shown())
		if held != null and _is_the_same(held, entry):
			chosen = _entries.size()

	# An attribute nobody declares is added at the end and selected, so what is
	# on screen is what is stored - and coloured, so it does not read as a
	# choice somebody meant to make.
	if chosen == 0 and GameplayAttributeCatalog.is_unknown(held):
		_unknown = held
		_choices.add_item(UNKNOWN % held.attribute_name)
		chosen = _choices.item_count - 1
		_choices.add_theme_color_override(FONT_COLOR, WRONG)
	else:
		_choices.remove_theme_color_override(FONT_COLOR)

	_choices.select(chosen)


static func _is_the_same(
	held: GameplayAttributeRef, entry: GameplayAttributeCatalog.Entry
) -> bool:
	if held.attribute_name != entry.attribute_name:
		return false
	return held.set_name == &"" or held.set_name == entry.set_name


func _on_chosen(index: int) -> void:
	# The unknown entry is at the end, past everything the catalogue offered:
	# selecting it means "leave what is there", which is what it is showing.
	if index <= 0 or index > _entries.size():
		return
	emit_changed(get_edited_property(), _entries[index - 1].as_reference())
