## The control a person actually types a value into.
##
## One field, one row: a checkbox for a bool, a number box for a number, a
## colour swatch for a colour. What decides which is not the type on its own but
## whether the text that is *there* can be read as that type - a `float`
## argument holding `pick.strength` is an expression, and a SpinBox over it
## would be a control that cannot show what is written and destroys it the
## moment it is touched. Those fall back to a plain line, which shows the
## expression and hands it back unharmed.
##
## Nothing here decides what happens to the file. The control says what it now
## means, as GDScript, and emits it; whether that becomes an edit is the
## screen's business and the document's. So the value shown is never authority -
## it is a picture of a line in a file, and the file is the original.
##
## The one piece of remembered state is the text this was configured with, kept
## only so Escape can put it back during one editing session. It is thrown away
## whenever the card is rebuilt, because by then the file has moved on and a
## remembered value would be older than the thing it claims to restore.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerValueEditor extends HBoxContainer

## What this row means once somebody has finished changing it, as GDScript.
##
## Emitted on a deliberate finish - Enter, focus leaving, a box being ticked -
## and never per keystroke. Every one of these becomes a commit with an undo
## behind it, and a person dragging a spinner through forty values should not
## have to press Ctrl-Z forty times.
signal committed(source_text: String)

const RESOURCE_PICKER: String = "EditorResourcePicker"

const COMPONENT_WIDTH: float = 58.0


## The order a vector's components are written in, which is also the order they
## are read back in. One list rather than two, so a four-component vector cannot
## be built one way and read the other.
const COMPONENTS: Array[String] = ["x", "y", "z", "w"]

## The field this row was configured for, copied rather than held.
##
## A copy because the live one belongs to a graph that is redrawn under this
## row, and because Escape has to rebuild the control from the whole contract:
## remembering four of its ten parts is how pressing Escape on a resource or a
## dropdown used to hand back a plain text box.
var _field: ComposerNode.Field = ComposerNode.Field.new()
var _editable: bool = true
var _shape: ComposerValueShape.Kind = ComposerValueShape.Kind.RAW
var _original: String = ""
var _control: Control = null
var _components: Array[SpinBox] = []


#region Building
## Put the right control in this row for `field`.
func configure(field: ComposerNode.Field, editable: bool = true) -> void:
	# Detached before it is freed. `queue_free` happens at the end of the frame,
	# so a control only queued is still a child, still laid out, still findable by
	# index and still able to emit - and this row is read by index in the same
	# frame it is configured.
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_components.clear()
	_control = null

	_field = _copy_of(field)
	_editable = editable
	# A required value the file never passed has no text to show, and a row
	# holding nothing is a row nobody can fill in. It is offered as what it would
	# have been created holding, so the control is the one that argument deserves
	# and committing it repairs the call. The field this was handed is not
	# touched: it belongs to a graph, and changing it to draw it would make the
	# card disagree with the panel about what the file says.
	if not _field.is_satisfied():
		_field.display = ComposerWriter.declared_default(_field)
		_field.source = ComposerNode.ValueSource.LITERAL
	_original = _field.display
	_shape = (
		ComposerValueShape.of(_field) if editable else ComposerValueShape.Kind.WIRED
	)
	_build(_field)


## Everything the engine said about an argument, on a field of this row's own.
##
## Every part of it, because every part decides something: the hint picks the
## control, the class narrows a picker, the default is what an absent value is
## offered as. A copy that dropped one of them would work until somebody
## pressed Escape.
static func _copy_of(field: ComposerNode.Field) -> ComposerNode.Field:
	var made: ComposerNode.Field = ComposerNode.Field.new()
	made.label = field.label
	made.type_name = field.type_name
	made.display = field.display
	made.source = field.source
	made.editable = field.editable
	ComposerNodeFields.declare(made, field)
	return made


func _build(field: ComposerNode.Field) -> void:
	match _shape:
		ComposerValueShape.Kind.WIRED:
			_control = _shown(field.display)
		ComposerValueShape.Kind.BOOL:
			_control = _tick(field.display)
		ComposerValueShape.Kind.ENUM:
			_control = _choices(field)
		ComposerValueShape.Kind.NUMBER:
			_control = _number(field.display)
		ComposerValueShape.Kind.VECTOR:
			_control = _vector(field.display)
		ComposerValueShape.Kind.COLOUR:
			_control = _swatch(field.display)
		ComposerValueShape.Kind.RESOURCE:
			_control = _picker(field.display)
		ComposerValueShape.Kind.TEXT:
			_control = _line(_human(field.display))
		_:
			_control = _line(field.display)
	if _control != null:
		add_child(_control)


## The text of the field, with the delimiters a person should not have to type.
##
## `&"fire"` is shown as `fire`. The marks go back on at commit through the
## codec, so the one place that knows how a StringName is spelled is the one
## place that spells it.
func _human(written: String) -> String:
	var read: Dictionary = ComposerValueCodec.read_as(_field.type_name, written)
	if not read[ComposerValueCodec.OK]:
		return written

	# Named apart rather than run through one `String()`. The three types that
	# reach here are three different built-ins, and converting a Variant without
	# saying which is the dynamic boundary this project's typing rules exist to
	# keep out of its own code.
	var value: Variant = read[ComposerValueCodec.VALUE]
	if value is StringName:
		var named: StringName = value
		return String(named)
	if value is NodePath:
		var path: NodePath = value
		return String(path)
	if value is String:
		var text: String = value
		return text
	return written
#endregion


#region Saying what it now means
## What the control means, as the GDScript that would be written for it.
func source_text() -> String:
	match _shape:
		ComposerValueShape.Kind.BOOL:
			var tick: CheckBox = _control as CheckBox
			return ComposerValueCodec.encode_variant(tick.button_pressed, _field.type_name)
		ComposerValueShape.Kind.ENUM:
			return _enum_text()
		ComposerValueShape.Kind.NUMBER:
			return _number_text()
		ComposerValueShape.Kind.VECTOR:
			return _vector_text()
		ComposerValueShape.Kind.COLOUR:
			var swatch: ColorPickerButton = _control as ColorPickerButton
			return ComposerValueCodec.encode_variant(swatch.color, _field.type_name)
		ComposerValueShape.Kind.RESOURCE:
			return _resource_text()
		ComposerValueShape.Kind.TEXT:
			var typed: LineEdit = _control as LineEdit
			return ComposerValueCodec.encode_variant(typed.text, _field.type_name)
		ComposerValueShape.Kind.RAW:
			var raw: LineEdit = _control as LineEdit
			return raw.text
	return _original


## The number the chosen option stands for, written out.
##
## Never the name. Reflection does not say which enum a hint came from, so a
## symbol written back here would name an owner nobody said - and the file has
## to keep compiling for people who never open this tool.
func _enum_text() -> String:
	var chosen: OptionButton = _control as OptionButton
	if chosen == null or chosen.selected < 0:
		return _original
	var held: Variant = chosen.get_item_metadata(chosen.selected)
	return str(held if held is int else 0)


func _number_text() -> String:
	var spin: SpinBox = _control as SpinBox
	if _field.type_name == ComposerTypes.INT:
		return ComposerValueCodec.encode_variant(int(spin.value), _field.type_name)
	return ComposerValueCodec.encode_variant(spin.value, _field.type_name)


func _vector_text() -> String:
	var written: PackedStringArray = PackedStringArray()
	for box: SpinBox in _components:
		written.append(
			str(int(box.value)) if ComposerNumberBox.holds_integers(_field.type_name)
			else ComposerValueCodec.encode_variant(
				box.value, ComposerTypes.FLOAT
			)
		)
	return "%s(%s)" % [_field.type_name, ", ".join(written)]


func _resource_text() -> String:
	var chosen: Resource = _control.get(&"edited_resource")
	if chosen == null:
		return ComposerTypes.NOTHING
	# A resource nobody saved cannot be named, so it cannot be written. Rejected
	# rather than serialised inline: an ability that carried a copy of an effect
	# would stop tracking the effect the moment somebody edited the original.
	var written: String = ComposerValueCodec.encode_variant(chosen, _field.type_name)
	return written if not written.is_empty() else _original


## Put the text back the way it was configured. Escape, and nothing else.
##
## Rebuilt from the snapshot, so what comes back is the control that was
## there: a picker stays a picker and a dropdown stays a dropdown.
func reset_to(source_text: String) -> void:
	var field: ComposerNode.Field = _copy_of(_field)
	field.display = source_text
	configure(field, _editable)
#endregion


#region The controls
## Say what this row now means, if it means something new.
##
## Focus leaves a control every time somebody clicks past it, and every commit is
## a write with an undo behind it. Without this, tabbing through an ability marks
## every statement it passes as edited and fills the history with changes nobody
## made.
func _finished() -> void:
	var written: String = source_text()
	if written == _original:
		return
	_original = written
	committed.emit(written)


func _shown(written: String) -> Control:
	var label: Label = Label.new()
	label.text = written
	label.add_theme_color_override(GASEditorTheme.FONT_COLOR, ComposerTheme.TEXT_DIM)
	label.add_theme_font_size_override(
		GASEditorTheme.FONT_SIZE, ComposerTheme.FONT_VALUE
	)
	return label


## Say how big the text in this control is.
##
## Every control here is one of Godot's, and Godot's controls read their font
## off whatever theme they are standing in. Inside the editor that reads right
## by accident; inside a project whose theme says something else, a number box
## came out taller than the card holding it. A control that draws text says its
## own size, here, once.
func _sized(control: Control) -> Control:
	control.add_theme_font_size_override(
		GASEditorTheme.FONT_SIZE, ComposerTheme.FONT_VALUE
	)
	var spin: SpinBox = control as SpinBox
	if spin != null:
		spin.get_line_edit().add_theme_font_size_override(
			GASEditorTheme.FONT_SIZE, ComposerTheme.FONT_VALUE
		)
	return control


func _line(written: String) -> Control:
	var typed: LineEdit = LineEdit.new()
	typed.text = written
	typed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sized(typed)
	typed.text_submitted.connect(func _entered(_text: String) -> void: _finished())
	typed.focus_exited.connect(_finished)
	_let_escape_undo(typed)
	return typed


## A tick confirms as it is ticked. There is no later moment to take it as
## finished: a checkbox that waited for focus to leave would look set and not be.
func _tick(written: String) -> Control:
	var box: CheckBox = CheckBox.new()
	var read: Dictionary = ComposerValueCodec.parse_bool(written)
	box.button_pressed = read[ComposerValueCodec.VALUE] if read[ComposerValueCodec.OK] else false
	box.toggled.connect(func _flipped(_on: bool) -> void: _finished())
	return _sized(box)


## Every name the hint offers, with the number each one means behind it.
func _choices(field: ComposerNode.Field) -> Control:
	var options: Array[ComposerEnumHint.Option] = ComposerEnumHint.parse(
		field.hint_string
	)
	var chosen: OptionButton = OptionButton.new()
	for option: ComposerEnumHint.Option in options:
		chosen.add_item(option.label)
		chosen.set_item_metadata(chosen.item_count - 1, option.value)
	chosen.selected = ComposerEnumHint.value_index(
		options, field.display.strip_edges().to_int()
	)
	chosen.item_selected.connect(func _picked(_index: int) -> void: _finished())
	return _sized(chosen)


func _number(written: String) -> Control:
	var spin: SpinBox = _spin(written)
	var read: Dictionary = ComposerValueCodec.read_as(_field.type_name, written)
	if read[ComposerValueCodec.OK]:
		spin.value = read[ComposerValueCodec.VALUE]
	ComposerNumberBox.ranged(spin, _field)
	return spin


## One box per component, in the order they are written.
func _vector(written: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var read: Dictionary = ComposerValueCodec.read_as(_field.type_name, written)
	var wanted: int = ComposerValueShape.SIZES[_field.type_name]
	for position: int in wanted:
		var box: SpinBox = _spin(written)
		box.custom_minimum_size = Vector2(COMPONENT_WIDTH, 0.0)
		if read[ComposerValueCodec.OK]:
			box.value = _component(read[ComposerValueCodec.VALUE], position)
		_components.append(box)
		row.add_child(box)
	return row


## One component of a vector, by the name it is written with.
##
## Indexed rather than reached for by method: a Vector2 is a built-in value, not
## an object, and only the index form works on one.
static func _component(value: Variant, position: int) -> float:
	var found: Variant = value[COMPONENTS[position]]
	return found


func _swatch(written: String) -> Control:
	var button: ColorPickerButton = ColorPickerButton.new()
	var read: Dictionary = ComposerValueCodec.parse_color(written)
	if read[ComposerValueCodec.OK]:
		button.color = read[ComposerValueCodec.VALUE]
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# When the popup shuts, not while it is open. A picker being dragged around
	# a colour wheel emits continuously, and every one of those would be a
	# separate thing to undo.
	button.popup_closed.connect(_finished)
	return _sized(button)


## A picker exists only inside a running editor. Outside one - a test, a tool
## run - the field falls back to its text rather than to nothing, so what is in
## the file stays visible and editable wherever this is built.
func _picker(written: String) -> Control:
	if not ClassDB.can_instantiate(RESOURCE_PICKER):
		_shape = ComposerValueShape.Kind.RAW
		return _line(written)
	var picker: Control = ClassDB.instantiate(RESOURCE_PICKER)
	picker.set(&"base_type", String(_field.type_name))
	picker.set(&"edited_resource", _loaded(written))
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.connect(&"resource_changed", func _chosen(_resource: Resource) -> void: _finished())
	return _sized(picker)


## The resource a `preload("...")` names, or nothing.
static func _loaded(written: String) -> Resource:
	var text: String = written.strip_edges()
	if not text.begins_with(ComposerValueCodec.PRELOAD_OPEN):
		return null
	var path: String = text.substr(
		ComposerValueCodec.PRELOAD_OPEN.length(),
		text.length()
		- ComposerValueCodec.PRELOAD_OPEN.length()
		- ComposerValueCodec.PRELOAD_SHUT.length()
	)
	if not ResourceLoader.exists(path):
		return null
	return load(path)


func _spin(written: String) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	var whole: bool = ComposerNumberBox.holds_integers(_field.type_name)
	spin.rounded = whole
	spin.step = (
		ComposerNumberBox.WHOLE_STEP if whole else ComposerNumberBox.step_for(written)
	)
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# `apply()` first, every time. These signals come from the SpinBox's own line
	# edit and fire while the typed text is still text: reading `value` here
	# without asking the box to parse it returns the number from before the edit,
	# so a typed one is dropped and the previous one is committed in its place.
	spin.get_line_edit().text_submitted.connect(
		func _entered(_text: String) -> void: _settled(spin)
	)
	spin.get_line_edit().focus_exited.connect(func _left() -> void: _settled(spin))
	_sized(spin)
	_let_escape_undo(spin.get_line_edit())
	return spin


func _settled(spin: SpinBox) -> void:
	spin.apply()
	_finished()


## Escape puts back the text this row was configured with.
##
## The only thing `_original` is kept for. Bound to the control rather than to the
## row, because the key has to be caught where the caret is - a handler on the
## container never sees it while a LineEdit has focus, which is exactly when
## somebody presses Escape.
func _let_escape_undo(control: Control) -> void:
	control.gui_input.connect(
		func _pressed(event: InputEvent) -> void:
			if not event.is_action_pressed(ComposerKeys.CANCEL):
				return
			var restore: String = _original
			reset_to(restore)
			control.accept_event()
	)


#endregion
