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
const RANGE_PARTS: int = 3
const OR_GREATER: String = "or_greater"
const OR_LESS: String = "or_less"
const INT_STEP: float = 1.0
const FLOAT_STEP: float = 0.01

## As far as a step is allowed to shrink. A float carries about seven decimal
## digits, so a step below this is precision the number never had.
const MOST_DECIMALS: int = 6
const COMPONENT_WIDTH: float = 58.0

## The vector types written with whole components.
const INTEGER_VECTORS: Array[StringName] = [
	ComposerTypes.VECTOR2I, ComposerTypes.VECTOR3I, ComposerTypes.VECTOR4I,
]

## The order a vector's components are written in, which is also the order they
## are read back in. One list rather than two, so a four-component vector cannot
## be built one way and read the other.
const COMPONENTS: Array[String] = ["x", "y", "z", "w"]

var _type_name: StringName = &""
var _variant_type: int = TYPE_NIL
var _hint: int = PROPERTY_HINT_NONE
var _hint_string: String = ""
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

	_type_name = field.type_name
	_variant_type = field.variant_type
	_hint = field.hint
	_hint_string = field.hint_string
	_original = field.display
	_shape = ComposerValueShape.of(field) if editable else ComposerValueShape.Kind.WIRED
	_build(field)


func _build(field: ComposerNode.Field) -> void:
	match _shape:
		ComposerValueShape.Kind.WIRED:
			_control = _shown(field.display)
		ComposerValueShape.Kind.BOOL:
			_control = _tick(field.display)
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
	var read: Dictionary = ComposerValueCodec.read_as(_type_name, written)
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
			return ComposerValueCodec.encode_variant(tick.button_pressed, _type_name)
		ComposerValueShape.Kind.NUMBER:
			return _number_text()
		ComposerValueShape.Kind.VECTOR:
			return _vector_text()
		ComposerValueShape.Kind.COLOUR:
			var swatch: ColorPickerButton = _control as ColorPickerButton
			return ComposerValueCodec.encode_variant(swatch.color, _type_name)
		ComposerValueShape.Kind.RESOURCE:
			return _resource_text()
		ComposerValueShape.Kind.TEXT:
			var typed: LineEdit = _control as LineEdit
			return ComposerValueCodec.encode_variant(typed.text, _type_name)
		ComposerValueShape.Kind.RAW:
			var raw: LineEdit = _control as LineEdit
			return raw.text
	return _original


func _number_text() -> String:
	var spin: SpinBox = _control as SpinBox
	if _type_name == ComposerTypes.INT:
		return ComposerValueCodec.encode_variant(int(spin.value), _type_name)
	return ComposerValueCodec.encode_variant(spin.value, _type_name)


func _vector_text() -> String:
	var written: PackedStringArray = PackedStringArray()
	for box: SpinBox in _components:
		written.append(
			str(int(box.value)) if _integer() else ComposerValueCodec.encode_variant(
				box.value, ComposerTypes.FLOAT
			)
		)
	return "%s(%s)" % [_type_name, ", ".join(written)]


func _resource_text() -> String:
	var chosen: Resource = _control.get(&"edited_resource")
	if chosen == null:
		return ComposerTypes.NOTHING
	# A resource nobody saved cannot be named, so it cannot be written. Rejected
	# rather than serialised inline: an ability that carried a copy of an effect
	# would stop tracking the effect the moment somebody edited the original.
	var written: String = ComposerValueCodec.encode_variant(chosen, _type_name)
	return written if not written.is_empty() else _original


## Put the text back the way it was configured. Escape, and nothing else.
func reset_to(source_text: String) -> void:
	var field: ComposerNode.Field = ComposerNode.Field.new()
	field.type_name = _type_name
	field.variant_type = _variant_type
	field.hint = _hint
	field.hint_string = _hint_string
	field.display = source_text
	configure(field)
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


func _line(written: String) -> Control:
	var typed: LineEdit = LineEdit.new()
	typed.text = written
	typed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	typed.add_theme_font_size_override(
		GASEditorTheme.FONT_SIZE, ComposerTheme.FONT_VALUE
	)
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
	return box


func _number(written: String) -> Control:
	var spin: SpinBox = _spin(written)
	var read: Dictionary = ComposerValueCodec.read_as(_type_name, written)
	if read[ComposerValueCodec.OK]:
		spin.value = read[ComposerValueCodec.VALUE]
	_ranged(spin)
	return spin


## One box per component, in the order they are written.
func _vector(written: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var read: Dictionary = ComposerValueCodec.read_as(_type_name, written)
	var wanted: int = ComposerValueShape.SIZES[_type_name]
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
	return button


## A picker exists only inside a running editor. Outside one - a test, a tool
## run - the field falls back to its text rather than to nothing, so what is in
## the file stays visible and editable wherever this is built.
func _picker(written: String) -> Control:
	if not ClassDB.can_instantiate(RESOURCE_PICKER):
		_shape = ComposerValueShape.Kind.RAW
		return _line(written)
	var picker: Control = ClassDB.instantiate(RESOURCE_PICKER)
	picker.set(&"base_type", String(_type_name))
	picker.set(&"edited_resource", _loaded(written))
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.connect(&"resource_changed", func _chosen(_resource: Resource) -> void: _finished())
	return picker


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


## The smallest step that can still hold `written` exactly.
##
## Godot rounds a Range's value to a multiple of its step on every assignment, so
## a box stepping by 0.01 turns the literal 0.7071 into 0.71 the instant it is
## loaded - a normalised direction quietly destroyed by opening the card that
## holds it. The step follows the number the file actually contains; a range the
## method declared still overrides it afterwards.
static func _step_for(written: String) -> float:
	var fraction: String = written.strip_edges().get_slice(".", 1)
	if fraction.is_empty():
		return FLOAT_STEP
	return minf(FLOAT_STEP, pow(0.1, mini(fraction.length(), MOST_DECIMALS)))


func _spin(written: String) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.rounded = _integer()
	spin.step = INT_STEP if _integer() else _step_for(written)
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
			if not event.is_action_pressed(&"ui_cancel"):
				return
			var restore: String = _original
			reset_to(restore)
			control.accept_event()
	)


## Apply the range the engine declared, when it declared one.
##
## `or_greater` and `or_less` are what the declaring method said about its own
## bounds, so they are obeyed rather than assumed: a range without them means
## the author meant the limits.
func _ranged(spin: SpinBox) -> void:
	if _hint != PROPERTY_HINT_RANGE:
		return
	var parts: PackedStringArray = _hint_string.split(",")
	if parts.size() < RANGE_PARTS - 1:
		return
	if not parts[0].is_valid_float() or not parts[1].is_valid_float():
		return
	spin.min_value = parts[0].to_float()
	spin.max_value = parts[1].to_float()
	if parts.size() >= RANGE_PARTS and parts[2].is_valid_float():
		spin.step = parts[2].to_float()
	spin.allow_greater = _hint_string.contains(OR_GREATER)
	spin.allow_lesser = _hint_string.contains(OR_LESS)


## Whether this argument holds whole numbers.
##
## Named against the actual integer vector types rather than tested for a
## trailing "i". A game is free to declare a class called `Yuki` or `Ashi`, and
## a spinner that rounded its value because of how the name ends is a control
## that quietly deletes the fraction of somebody's number.
func _integer() -> bool:
	if _type_name == ComposerTypes.INT:
		return true
	return INTEGER_VECTORS.has(_type_name)
#endregion
