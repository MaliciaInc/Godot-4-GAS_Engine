## One node, drawn as a real graph node.
##
## A GraphNode rather than a Control the canvas positions by hand. That is not a
## cosmetic choice: the pins, the wires between them, the dragging, the
## selection and the refusal of an impossible connection all come from the
## widget, so none of them can drift from what the canvas thinks is happening.
## The version this replaced drew its own cables and hit-tested its own cards,
## and every one of those was a second opinion about where a port was.
##
## A slot is a row. GraphNode numbers slots by child index and knows nothing
## about what a port means, so the two lists here are the whole translation
## between "the second pin on the left" and "the argument called Source Asc".
## Everything that leaves this card speaks the second language.
##
## Editing happens in the row, through the same control the Inspector uses. A
## card that showed values and a panel that edited them would be two pictures of
## one argument, and they would disagree the moment either was wrong.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerCard extends GraphNode

const AWAIT_LABEL: String = "await"
const MISSING_LABEL: String = "not connected"
const WIRED_MARK: String = "⌄"
const DOT_SIZE: float = 7.0
const DOT_RADIUS: float = 3.5

## How much of a card is worth drawing.
##
## Zoom alone is not enough, and it shows the moment anyone tries it: pulled
## back far enough to see the shape of a flow, the fields are smudges and the
## card is still spending its space drawing text nobody can read. Pulling back
## is for seeing the shape - how many branches, where they meet, what is red -
## and a block says that better than a full card does.
enum Detail { FULL, TITLE, BLOCK }

## What somebody typed into one of this card's rows, as GDScript.
##
## The card does not act on it. Whether it becomes an edit is the screen's
## business, because only the document can say whether the file may be written.
signal value_edited(node_id: StringName, position: int, source_text: String)

var node_id: StringName = &""

## What the pins on each side are, in slot order. A blank means that side of
## that row carries no pin.
var _left_port_ids: Array[StringName] = []
var _right_port_ids: Array[StringName] = []

var _ports: Dictionary[StringName, ComposerNode.Port] = {}
var _rows: Array[Control] = []
var _state: ComposerNode.State = ComposerNode.State.CLEAN


#region Building
## Draw `node`, with its pins typed by `port_types`.
func build(node: ComposerNode, port_types: ComposerPortTypes) -> void:
	node_id = node.id
	name = String(node.id)
	title = node.title + (" " + AWAIT_LABEL if node.awaits else "")
	_state = node.state
	_own_the_title()
	_clear()
	for pin: ComposerNode.Port in node.ports:
		_ports[pin.id] = pin

	# The title row is slot 0 and carries the run of control, so a card always
	# has somewhere for execution to arrive and leave even when it takes no
	# arguments at all.
	_add_row(_title_row(node), ComposerReader.EXEC_IN, ComposerReader.EXEC_OUT)
	for position: int in node.fields.size():
		# The pin is asked for rather than spelled. A call's argument pin carries
		# a number and a branch's condition does not, and a card that built the
		# name itself drew a row whose pin nothing could land on.
		var into: ComposerNode.Port = node.pin_for_field(position)
		_add_row(_field_row(node, position), into.id if into != null else &"", &"")
	if _ports.has(ComposerReader.VALUE_OUT):
		_add_row(_pin_row(_ports[ComposerReader.VALUE_OUT].label, true), &"", ComposerReader.VALUE_OUT)

	# One row per path out, in the order the projection put them on the node: a
	# branch's True and False, a match's arms and its No Match. Counted from the
	# node rather than from the kind of statement, so a match with five arms
	# draws five and nothing here has to know how many there are.
	for pin: ComposerNode.Port in node.ports:
		if not _is_a_path_out(pin):
			continue
		_add_row(_pin_row(pin.label, false), &"", pin.id)

	_apply_slots(port_types)


## Say how the title is drawn, rather than letting the host say it.
##
## The rows are this card's own controls and carry their own font. The title is
## GraphNode's, and the label it draws it in reads `font_size` off the ambient
## theme as any Label would - `title_font_size` sizes the bar, not the text
## inside it. In the Godot editor the ambient theme is the editor's and it
## happens to look right; in a game whose theme says Labels are 96, the same
## card came out with a title several times the height of the card. So the card
## carries a theme of its own, which is where that label finds its size. The
## default size in it is a floor and nothing more - a theme lower in the chain
## that names a type outright still wins, which is why the boxes somebody types
## into say their own size where they are built rather than relying on this.
## The rows are unaffected either way; every label this card builds already
## carries its own size.
func _own_the_title() -> void:
	add_theme_font_size_override(
		GASEditorTheme.TITLE_FONT_SIZE, ComposerTheme.FONT_TITLE
	)
	add_theme_color_override(GASEditorTheme.TITLE_COLOR, ComposerTheme.TEXT)

	var own: Theme = Theme.new()
	own.default_font_size = ComposerTheme.FONT_VALUE
	own.set_font_size(
		GASEditorTheme.FONT_SIZE, ComposerTheme.LABEL_TYPE, ComposerTheme.FONT_TITLE
	)
	own.set_color(
		GASEditorTheme.FONT_COLOR, ComposerTheme.LABEL_TYPE, ComposerTheme.TEXT
	)
	theme = own


## Put a row in, and remember which pins it carries.
##
## A named port the node does not actually have becomes a blank rather than a
## drawn pin: a `return` has no way out, and a card that offered one would be
## promising something GDScript will not keep.
func _add_row(row: Control, left: StringName, right: StringName) -> void:
	add_child(row)
	_rows.append(row)
	_left_port_ids.append(left if _ports.has(left) else &"")
	_right_port_ids.append(right if _ports.has(right) else &"")


## Tell GraphNode which pins to draw, in which colours.
##
## Done in one pass at the end rather than per row, because a slot is addressed
## by its index and the indices are only settled once every row is in.
func _apply_slots(port_types: ComposerPortTypes) -> void:
	for slot: int in _rows.size():
		var left: ComposerNode.Port = _found(_left_port_ids[slot])
		var right: ComposerNode.Port = _found(_right_port_ids[slot])
		set_slot(
			slot,
			left != null,
			port_types.ui_type(left.type_name, left.kind) if left != null else 0,
			(
				port_types.color_for(left.type_name, left.kind) if left != null
				else ComposerTheme.TRANSPARENT
			),
			right != null,
			port_types.ui_type(right.type_name, right.kind) if right != null else 0,
			(
				port_types.color_for(right.type_name, right.kind) if right != null
				else ComposerTheme.TRANSPARENT
			)
		)


func _found(port_id: StringName) -> ComposerNode.Port:
	if port_id.is_empty() or not _ports.has(port_id):
		return null
	return _ports[port_id]


func _clear() -> void:
	for row: Control in _rows:
		remove_child(row)
		row.queue_free()
	# The slots go too. GraphNode keeps its own table of which rows draw pins, and
	# a rebuild that left it behind would draw the old card's pins on the new
	# card's rows - so a card rebuilt into a shorter statement keeps offering the
	# arguments the longer one had.
	clear_all_slots()
	_rows.clear()
	_left_port_ids.clear()
	_right_port_ids.clear()
	_ports.clear()
#endregion


#region Which pin is which
## The semantic port on the left of slot `index`, or nothing.
func port_id_for_left_index(index: int) -> StringName:
	if index < 0 or index >= _left_port_ids.size():
		return &""
	return _left_port_ids[index]


func port_id_for_right_index(index: int) -> StringName:
	if index < 0 or index >= _right_port_ids.size():
		return &""
	return _right_port_ids[index]


## Which of the drawn input pins this port is.
##
## Counted rather than taken from the slot: GraphNode numbers the pins it draws,
## not the rows, so a card whose second row has no left pin has an input at
## index 1 belonging to its third row. Getting this wrong points every wire at
## the row above or below the one it belongs to.
func left_index_for_port(port_id: StringName) -> int:
	return _drawn_index(_left_port_ids, port_id)


func right_index_for_port(port_id: StringName) -> int:
	return _drawn_index(_right_port_ids, port_id)


## The semantic port that drawn input `index` stands for.
func left_port_of_drawn(index: int) -> StringName:
	return _drawn_port(_left_port_ids, index)


func right_port_of_drawn(index: int) -> StringName:
	return _drawn_port(_right_port_ids, index)


static func _drawn_index(ids: Array[StringName], port_id: StringName) -> int:
	if port_id.is_empty():
		return -1
	var drawn: int = 0
	for slot: int in ids.size():
		if ids[slot].is_empty():
			continue
		if ids[slot] == port_id:
			return drawn
		drawn += 1
	return -1


static func _drawn_port(ids: Array[StringName], index: int) -> StringName:
	var drawn: int = 0
	for slot: int in ids.size():
		if ids[slot].is_empty():
			continue
		if drawn == index:
			return ids[slot]
		drawn += 1
	return &""


## Where a pin sits, in this card's own coordinates.
func graph_port_position(port_id: StringName) -> Vector2:
	var incoming: int = left_index_for_port(port_id)
	if incoming >= 0:
		return get_input_port_position(incoming)
	var outgoing: int = right_index_for_port(port_id)
	if outgoing >= 0:
		return get_output_port_position(outgoing)
	return Vector2.ZERO
#endregion


#region Rows
## The state dot. The title itself is GraphNode's, so it is not drawn twice.
func _title_row(node: ComposerNode) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(
		GASEditorTheme.SEPARATION, int(ComposerTheme.S2 + 1.0)
	)

	var holder: CenterContainer = CenterContainer.new()
	var dot: Panel = Panel.new()
	dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
	dot.add_theme_stylebox_override(
		GASEditorTheme.PANEL_STYLEBOX,
		ComposerTheme.disc(
			ComposerTheme.severity_color(ComposerNode.severity_of(node.state)),
			DOT_RADIUS
		)
	)
	holder.add_child(dot)
	row.add_child(holder)
	return row


## An argument: its name, and either a control to set it or what is absent.
func _field_row(node: ComposerNode, position: int) -> Control:
	var field: ComposerNode.Field = node.fields[position]
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(GASEditorTheme.SEPARATION, int(ComposerTheme.S1))
	column.add_child(
		_label(field.label, ComposerTheme.TEXT_DIM, ComposerTheme.FONT_LABEL)
	)

	if not field.is_satisfied():
		# A required value that is absent is an error and is drawn as one. There
		# is no control, because there is nothing there to show in one.
		column.add_child(_label(
			MISSING_LABEL,
			ComposerTheme.severity_color(ComposerGraph.Severity.ERROR),
			ComposerTheme.FONT_VALUE
		))
		return column

	var editor: ComposerValueEditor = ComposerValueEditor.new()
	column.add_child(editor)
	editor.configure(field, node.may_edit(field))
	editor.committed.connect(
		func _typed(source_text: String) -> void:
			value_edited.emit(node_id, position, source_text)
	)
	return column


## A pin on the right, with the name a person reads it by.
##
## The local a statement declares, and every path a branch or a match can take.
## They are the same row because they are the same thing to somebody looking at
## the card: a place on the right hand side that a cable leaves from, with a word
## beside it saying which one it is. Only a value carries the mark.
func _pin_row(named: String, produced: bool) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_label(named, ComposerTheme.TEXT, ComposerTheme.FONT_VALUE))
	if produced:
		row.add_child(_label(WIRED_MARK, ComposerTheme.TEXT_DIM, ComposerTheme.FONT_VALUE))
	return row


## Whether that pin is a path this statement can take, rather than the one way
## out an ordinary statement has.
##
## The generic way out lives on the title row, which every card has. A branch
## does not have one at all - it leaves by True or by False - so what is left
## here is exactly the pins that need a row of their own.
static func _is_a_path_out(pin: ComposerNode.Port) -> bool:
	return (
		pin.is_execution()
		and pin.direction == ComposerNode.PortDirection.OUTPUT
		and pin.id != ComposerReader.EXEC_OUT
	)


static func _label(text: String, tint: Color, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override(GASEditorTheme.FONT_COLOR, tint)
	label.add_theme_font_size_override(GASEditorTheme.FONT_SIZE, font_size)
	return label
#endregion


#region How much to draw
## Draw as much of this card as is worth reading at the current zoom.
##
## The card keeps the size it measured at, whatever is hidden. Shrinking it as
## its contents go away would move every pin on it and every wire with them, so
## the graph would appear to rearrange itself while somebody was only pulling
## back to look at it.
func show_detail(level: ComposerCard.Detail) -> void:
	var full: bool = level == ComposerCard.Detail.FULL
	for slot: int in _rows.size():
		# Faded, never hidden. A hidden child leaves GraphNode's slot list, so
		# every pin below it renumbers - and the canvas fixed its wire indices
		# once, when the graph was drawn. Pulling back to look at an ability
		# would silently re-point every cable on it.
		#
		# Slot 0 is the name, and it is what tells the three levels apart: read at
		# FULL, named at TITLE, and at BLOCK nothing but the coloured shape -
		# which is the whole point of pulling back that far.
		var lit: bool = full or (slot == 0 and level == ComposerCard.Detail.TITLE)
		_rows[slot].modulate.a = 1.0 if lit else 0.0
		_rows[slot].mouse_filter = (
			Control.MOUSE_FILTER_STOP if full else Control.MOUSE_FILTER_IGNORE
		)
	modulate = (
		ComposerTheme.severity_color(ComposerNode.severity_of(_state))
		if level == ComposerCard.Detail.BLOCK
		else Color.WHITE
	)
#endregion
