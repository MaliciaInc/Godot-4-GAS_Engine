## Cases 4 to 9 of the smoke: everything that happens on a pin.
##
## Split out of `composer_smoke.gd` because pins need arithmetic of their own
## and the file would be past the size this project keeps to. It borrows the
## harness rather than owning anything: the screen, the hand and the report are
## all the harness's, so a check here reads the same as a check there.
##
## The arithmetic is the engine's own, and it is not guessed at: `GraphNode`
## reports a port's place in the card's unscaled space, the card is drawn at
## `position` - which already carries scroll and zoom - and everything on it is
## scaled by the zoom. So a pin is at `card.position + port * zoom`, and the
## canvas's own origin puts that on the window.
##
## @meta_license: MIT
extends RefCounted

const Input_ = preload("res://test/composer_input.gd")

## An ability of this addon's own that actually feeds one statement from
## another, which is the only place a data cable can be picked up.
const WITH_A_CABLE: String = "res://addons/GAS_Engine/reference/sweeping_volley.gd"
const COPY: String = "user://composer_smoke_wires.gd"

var _it: Node = null


func _init(harness: Node) -> void:
	_it = harness


func run() -> void:
	await case_4_break()
	await case_5_reconnect()
	await case_6_ctrl_move()
	await case_7_data_pin()
	await case_8_incompatible()
	await case_9_pin_to_empty()


#region Where a pin is
## A pin's place on the window, ready to be clicked.
func pin(node_id: StringName, port_id: StringName, outgoing: bool) -> Vector2:
	var card: ComposerCard = _it.card(node_id)
	if card == null:
		return Vector2.ZERO
	var index: int = (
		card.right_index_for_port(port_id) if outgoing
		else card.left_index_for_port(port_id)
	)
	if index < 0:
		return Vector2.ZERO
	var local: Vector2 = (
		card.get_output_port_position(index) if outgoing
		else card.get_input_port_position(index)
	)
	var canvas: ComposerCanvas = _it.canvas()
	return _it.hand.at(
		canvas.get_global_rect().position + card.position + local * canvas.zoom
	)


## Which pin the engine itself finds at the point we are about to click.
##
## The reverse of `pin()`, asked of the Composer's own arithmetic. A gesture
## that lands within reach of a neighbour's pin does something quietly correct
## to the wrong pin, and from the outside that is indistinguishable from a
## gesture the editor ignored.
func aims_at(node_id: StringName, port_id: StringName, outgoing: bool) -> String:
	var canvas: ComposerCanvas = _it.canvas()
	var cards: Dictionary[StringName, ComposerCard] = {}
	for child: Node in canvas.get_children():
		var card: ComposerCard = child as ComposerCard
		if card != null:
			cards[card.node_id] = card
	var here: ComposerCard = cards.get(node_id, null)
	if here == null:
		return "no card"
	var index: int = (
		here.right_index_for_port(port_id) if outgoing
		else here.left_index_for_port(port_id)
	)
	if index < 0:
		return "no pin"
	var local: Vector2 = (
		here.get_output_port_position(index) if outgoing
		else here.get_input_port_position(index)
	)
	var found: ComposerPins.Pin = ComposerPins.at(
		cards, canvas.zoom, here.position + local * canvas.zoom
	)
	if not found.is_found():
		return "nothing"
	return "%s.%s%s" % [found.node_id, found.port_id, "" if found.is_output == outgoing else " (other side)"]


## The first execution pin on one side of a node.
func exec_pin_of(node: ComposerNode, outgoing: bool) -> StringName:
	var wanted: ComposerNode.PortDirection = (
		ComposerNode.PortDirection.OUTPUT if outgoing
		else ComposerNode.PortDirection.INPUT
	)
	for port: ComposerNode.Port in node.ports:
		if port.is_execution() and port.direction == wanted:
			return port.id
	return &""


func wired(from: StringName, to: StringName) -> bool:
	for wire: ComposerGraph.Connection in _it.screen.graph().connections:
		if StringName(wire.from_node) == from and StringName(wire.to_node) == to:
			return true
	return false
#endregion


#region Case 4 · Clearing a pin
## Alt over an execution pin takes every cable off it. What is left has to be a
## graph somebody can still read and a file GDScript still compiles - a
## detached statement is allowed, a broken file is not.
func case_4_break() -> void:
	await _it.open_copy(_it.ABILITY, COPY)
	var first: ComposerNode = _it.statements()[0]
	var port: StringName = exec_pin_of(first, true)
	var wires: int = _it.screen.graph().connections.size()
	var body: String = _it.screen.printed()

	_it.check("4 · a statement has an execution pin", port != &"", String(port))
	if port == &"":
		return

	_it.clear_refusal()
	await _it.hand.click(pin(first.id, port, true), MOUSE_BUTTON_LEFT, Input_.ALT)
	await _it.hand.frames(6)

	var after: int = _it.screen.graph().connections.size()
	_it.check("4 · Alt over a pin takes its cables off", after < wires,
		"%d -> %d wires" % [wires, after])
	_it.check("4 · what is left still reads back", _it.screen.graph().is_editable(),
		_it.screen.graph().blocked_reason())
	# Not "does GDScript compile it": a script built in memory has no resource
	# path, so an ability's own exported types never resolve and the answer is
	# the same before and after any edit. What is true and worth asking is that
	# the Composer can still read what it wrote, and print it back unchanged.
	_it.check("4 · and the Composer can print back what it wrote",
		_prints_back(_it.screen.printed()))
	_it.check("4 · every statement is still in the file",
		_it.statements().size() == _statements_in(body),
		"%d of %d" % [_it.statements().size(), _statements_in(body)])
	await _it.shot("12-pin-cleared")

	await _it.screen.undo()
	await _it.hand.frames(4)
	_it.check("4 · undo puts the cables back",
		_it.screen.graph().connections.size() == wires,
		"%d wires" % _it.screen.graph().connections.size())

	await _it.screen.redo()
	await _it.hand.frames(4)
	_it.check("4 · redo takes them off again",
		_it.screen.graph().connections.size() == after,
		"%d wires" % _it.screen.graph().connections.size())


## Whether the text is one the Composer reads and writes back as it stands.
##
## The strongest thing a running game can ask. A round trip that changes a byte
## is a file somebody's next save would rewrite behind their back.
func _prints_back(source: String) -> bool:
	var read: ComposerGraph = ComposerReader.read(source, COPY)
	if not read.is_editable():
		return false
	var printed: ComposerWriter.Result = ComposerWriter.apply(read, source)
	return printed.is_ok() and printed.text == source


func _statements_in(source: String) -> int:
	var read: ComposerGraph = ComposerReader.read(source, COPY)
	var found: int = 0
	for node: ComposerNode in read.visible_nodes():
		found += 1 if node.source_backed else 0
	return found
#endregion


#region Case 5 · Putting one back
## Dragging one execution pin onto another is the widget's connection gesture.
## What it must produce is a change in the source - not a line on a canvas that
## the file knows nothing about - and one that survives being saved and read.
func case_5_reconnect() -> void:
	# Read again rather than carried over from case 4: a node's id is derived
	# from the line it sits on, so an edit renames every node after it.
	var statements: Array[ComposerNode] = _it.statements()
	var upstream: ComposerNode = statements[0]
	var downstream: ComposerNode = statements[1]
	var out: StringName = exec_pin_of(upstream, true)
	var into: StringName = exec_pin_of(downstream, false)
	if out == &"" or into == &"":
		_it.check("5 · there are two execution pins to join", false)
		return

	var before: String = _it.screen.printed()
	var joined: bool = wired(upstream.id, downstream.id)
	_it.check("5 · the cable this case reconnects is off", not joined)

	var from: Vector2 = pin(upstream.id, out, true)
	var to: Vector2 = pin(downstream.id, into, false)
	_it.check("5 · both pins are somewhere to aim at",
		from != Vector2.ZERO and to != Vector2.ZERO, "%s -> %s" % [from, to])

	# A gesture that produced nothing is two different stories - the widget
	# never read it as a connection, or it did and the file would not take it -
	# and only one of them is the Composer's.
	var gestures: Array[int] = [0, 0]
	_it.canvas().connection_drag_started.connect(
		func _began(_a: StringName, _b: int, _c: bool) -> void: gestures[0] += 1
	)
	_it.canvas().connection_request.connect(
		func _asked(_a: StringName, _b: int, _c: StringName, _d: int) -> void:
			gestures[1] += 1
	)
	_it.clear_refusal()
	await _it.hand.drag(from, to)
	await _it.hand.frames(6)

	_it.check("5 · the widget reads it as a connection gesture", gestures[0] > 0,
		"%d drags, %d requests" % [gestures[0], gestures[1]])
	_it.check("5 · dragging one pin onto another joins them",
		wired(_it.statements()[0].id, _it.statements()[1].id))
	_it.check("5 · and the source changed to say so", _it.screen.printed() != before)
	await _it.shot("13-reconnected")

	await _it.screen.save()
	await _it.screen.open(FileAccess.get_file_as_string(COPY), COPY)
	await _it.hand.frames(6)
	_it.check("5 · saving and opening keeps it",
		wired(_it.statements()[0].id, _it.statements()[1].id))
#endregion


#region Case 6 · Moving what is on a pin
## Ctrl carries every cable on one pin to another of the same direction, family
## and type.
##
## The direction the editor implements is producer to producer: pick up what a
## local feeds and hand all of it to a different local. Moving the *consuming*
## end - an argument's pin onto another argument's pin - is the same sentence in
## section 2.4 and is not implemented; it is written up as GAS-010 rather than
## asserted here, because a smoke that fails on a known gap says nothing new
## every time it runs.
##
## Execution is a third case and correctly refuses: carrying a run of control
## means rewriting the order statements are written in, which the editor says
## out loud instead of guessing at.
##
## Written here rather than borrowed from the reference set, because none of
## those declares two locals of one type with something reading one of them.
const TWO_PRODUCERS: String = """extends GameplayAbility

@export var damage: GameplayEffect


func _activate_ability() -> bool:
	var caster: Node2D = owner_asc.get_effect_target() as Node2D
	var sweep: GameplayOverlapRequest2D = GameplayOverlapRequest2D.new()
	var found: GameplayAbilityTargetData = GameplayTargetingService.overlap_2d(
		owner_asc, caster.get_world_2d(), sweep
	)
	var other: GameplayAbilityTargetData = GameplayTargetingService.overlap_2d(
		owner_asc, caster.get_world_2d(), sweep
	)
	apply_effect_to_targets(damage, found)
	end_ability()
	return true
"""

const MOVE_COPY: String = "user://composer_smoke_move.gd"


func case_6_ctrl_move() -> void:
	var out: FileAccess = FileAccess.open(MOVE_COPY, FileAccess.WRITE)
	out.store_string(TWO_PRODUCERS)
	out.close()
	await _it.screen.open(TWO_PRODUCERS, MOVE_COPY)
	await _it.hand.frames(6)

	var giving: ComposerNode = _producer_named("found")
	var instead: ComposerNode = _producer_named("other")
	var reading: ComposerNode = _consumer()
	_it.check("6 · one local is read and another is not",
		giving != null and instead != null and reading != null,
		"%s, %s, %s" % [giving != null, instead != null, reading != null])
	if giving == null or instead == null or reading == null:
		return
	_it.check("6 · the cable's pin is the one the engine finds there",
		aims_at(giving.id, ComposerReader.VALUE_OUT, true)
			== "%s.%s" % [giving.id, ComposerReader.VALUE_OUT])
	_it.check("6 · and so is the pin it is carried to",
		aims_at(instead.id, ComposerReader.VALUE_OUT, true)
			== "%s.%s" % [instead.id, ComposerReader.VALUE_OUT])

	var before: String = _it.screen.printed()
	var steps: int = _it.screen.history().depth()
	_it.clear_refusal()
	await _it.hand.drag(
		pin(giving.id, ComposerReader.VALUE_OUT, true),
		pin(instead.id, ComposerReader.VALUE_OUT, true),
		Input_.CTRL
	)
	await _it.hand.frames(6)

	_it.check("6 · what read one local now reads the other",
		_reads() == "other", "it reads %s" % _reads())
	_it.check("6 · in one step", _it.screen.history().depth() == steps + 1,
		"%d -> %d" % [steps, _it.screen.history().depth()])
	await _it.shot("14-cables-moved")

	await _it.screen.undo()
	await _it.hand.frames(4)
	_it.check("6 · and one undo returns the whole move", _it.screen.printed() == before)

	var untouched: String = _it.screen.printed()
	var depth: int = _it.screen.history().depth()
	_it.clear_refusal()
	await _it.hand.drag_and_cancel(
		pin(_producer_named("found").id, ComposerReader.VALUE_OUT, true),
		_it.empty_point(), Input_.CTRL
	)
	await _it.hand.frames(4)
	_it.check("6 · a move let go over nothing changes nothing",
		_it.screen.printed() == untouched)
	_it.check("6 · and leaves nothing to undo",
		_it.screen.history().depth() == depth,
		"%d -> %d" % [depth, _it.screen.history().depth()])


## The statement that declares a local of this name.
func _producer_named(local: String) -> ComposerNode:
	for node: ComposerNode in _it.statements():
		for port: ComposerNode.Port in node.ports:
			if port.id == ComposerReader.VALUE_OUT and port.label == local:
				return node
	return null


## The statement this case is about: the one applying the effect, which reads a
## local through its second argument.
##
## Named rather than "the first statement with a cable on it" - the two
## `overlap_2d` calls read a local as well, and they come first.
func _consumer() -> ComposerNode:
	for node: ComposerNode in _it.statements():
		if node.type_id == &"apply_effect_to_targets":
			return node
	return null


## The name of the local that statement reads now.
func _reads() -> String:
	var node: ComposerNode = _consumer()
	if node == null:
		return "nothing"
	for field: ComposerNode.Field in node.fields:
		if field.source == ComposerNode.ValueSource.WIRED:
			return field.display
	return "nothing"
#endregion


#region Case 7 · A data cable
## An argument fed by a cable reads as the local that produced it, and taking
## the cable off has to leave an argument the file can still hold.
func case_7_data_pin() -> void:
	await _it.open_copy(WITH_A_CABLE, COPY)
	var fed: ComposerNode = null
	var position: int = -1
	for node: ComposerNode in _it.statements():
		for index: int in node.fields.size():
			if node.fields[index].source == ComposerNode.ValueSource.WIRED:
				fed = node
				position = index
	_it.check("7 · this ability feeds one statement from another", fed != null,
		"%s" % [fed.title if fed != null else "none"])
	if fed == null:
		return

	var argument: StringName = StringName(ComposerReader.ARGUMENT % position)
	var written: String = fed.fields[position].display
	_it.check("7 · and the argument reads as the local that produced it",
		not written.is_empty(), written)
	await _it.shot("15-data-cable")

	var before: int = _it.screen.graph().connections.size()
	var aim: Vector2 = pin(fed.id, argument, false)
	_it.check("7 · the argument's pin is the one the engine finds there",
		aims_at(fed.id, argument, false) == "%s.%s" % [fed.id, argument],
		"aimed at %s.%s, engine finds %s" % [
			fed.id, argument, aims_at(fed.id, argument, false)
		])
	# Whether the canvas even heard it. A gesture the widget swallowed and a
	# gesture the Composer refused look identical from the file.
	var heard: Array[int] = [0]
	_it.canvas().gui_input.connect(func _got(_e: InputEvent) -> void: heard[0] += 1)
	_it.clear_refusal()
	await _it.hand.click(aim, MOUSE_BUTTON_LEFT, Input_.ALT)
	await _it.hand.frames(6)
	_it.check("7 · and the canvas heard the gesture", heard[0] > 0,
		"%d events reached it" % heard[0])

	_it.check("7 · Alt over the argument's pin takes the cable off",
		_it.screen.graph().connections.size() < before,
		"%d -> %d" % [before, _it.screen.graph().connections.size()])
	if _it.screen.graph().connections.size() == before:
		# GAS-009. Everything after this asks what the disconnect left behind,
		# and there was no disconnect - reporting those as failures too would
		# say the same open defect three times.
		return
	var after: ComposerNode = _it.screen.graph().find_node(fed.id)
	_it.check("7 · and leaves a value the file can hold",
		after != null and after.fields[position].source != ComposerNode.ValueSource.WIRED,
		"%s" % [after.fields[position].display if after != null else "gone"])
	_it.check("7 · with a file the Composer still prints back",
		_prints_back(_it.screen.printed()))
	await _it.shot("16-data-cable-off")
#endregion


#region Case 8 · A cable that cannot be
## Dragging a value into an argument that cannot hold it must change nothing:
## no cable, no source, and nothing added to the history for somebody to
## undo their way back through.
func case_8_incompatible() -> void:
	await _it.open_copy(WITH_A_CABLE, COPY)
	var pair: Array = _mismatched()
	_it.check("8 · this ability has two ends that do not fit", not pair.is_empty())
	if pair.is_empty():
		return

	var producer: ComposerNode = pair[0]
	var out: StringName = pair[1]
	var consumer: ComposerNode = pair[2]
	var into: StringName = pair[3]
	var before: String = _it.screen.printed()
	var wires: int = _it.screen.graph().connections.size()
	var steps: int = _it.screen.history().depth()

	await _it.hand.drag(pin(producer.id, out, true), pin(consumer.id, into, false))
	await _it.hand.frames(6)

	_it.check("8 · no cable is drawn",
		_it.screen.graph().connections.size() == wires,
		"%d wires" % _it.screen.graph().connections.size())
	_it.check("8 · the source is untouched", _it.screen.printed() == before)
	_it.check("8 · and there is nothing to undo",
		_it.screen.history().depth() == steps,
		"%d -> %d" % [steps, _it.screen.history().depth()])
	await _it.shot("17-refused")


## A value output and an argument that cannot take it.
func _mismatched() -> Array:
	for producer: ComposerNode in _it.statements():
		var out: StringName = _value_out_of(producer)
		if out == &"":
			continue
		var giving: StringName = _type_of(producer, out)
		for consumer: ComposerNode in _it.statements():
			if consumer.id == producer.id:
				continue
			for index: int in consumer.fields.size():
				var argument: StringName = StringName(ComposerReader.ARGUMENT % index)
				var taking: StringName = _type_of(consumer, argument)
				if taking == &"" or ComposerTypes.accepts(taking, giving):
					continue
				return [producer, out, consumer, argument]
	return []


func _value_out_of(node: ComposerNode) -> StringName:
	for port: ComposerNode.Port in node.ports:
		if not port.is_execution() and port.direction == ComposerNode.PortDirection.OUTPUT:
			return port.id
	return &""


func _type_of(node: ComposerNode, port_id: StringName) -> StringName:
	for port: ComposerNode.Port in node.ports:
		if port.id == port_id:
			return port.type_name
	return &""
#endregion


#region Case 9 · A pin let go over nothing
## Dragging from an argument into empty space asks what could fill it, and the
## list is filtered to what actually fits. Choosing one has to leave the new
## statement wired both ways - and be one thing to undo, not three.
func case_9_pin_to_empty() -> void:
	await _it.open_copy(WITH_A_CABLE, COPY)
	var consumer: ComposerNode = null
	var argument: StringName = &""
	for node: ComposerNode in _it.statements():
		for index: int in node.fields.size():
			var port: StringName = StringName(ComposerReader.ARGUMENT % index)
			if _type_of(node, port) != &"":
				consumer = node
				argument = port
				break
		if consumer != null:
			break
	_it.check("9 · there is an argument to fill", consumer != null, String(argument))
	if consumer == null:
		return

	var before: int = _it.statements().size()
	var steps: int = _it.screen.history().depth()
	await _it.hand.drag(pin(consumer.id, argument, false), _it.empty_point())
	await _it.hand.frames(6)

	var menu: ComposerActionMenu = _it._action_menu()
	_it.check("9 · letting go over nothing asks what could fill it",
		menu != null and menu.visible)
	await _it.shot("18-pin-to-empty")
	if menu == null or not menu.visible:
		return

	await _it.hand.key(KEY_ENTER)
	await _it.hand.frames(6)

	_it.check("9 · choosing one writes a statement",
		_it.statements().size() == before + 1,
		"%d -> %d" % [before, _it.statements().size()])
	_it.check("9 · and it is one thing to undo",
		_it.screen.history().depth() == steps + 1,
		"%d -> %d" % [steps, _it.screen.history().depth()])
	await _it.shot("19-made-from-pin")

	await _it.screen.undo()
	await _it.hand.frames(4)
	_it.check("9 · one undo takes the statement and its cables together",
		_it.statements().size() == before,
		"%d nodes" % _it.statements().size())
#endregion
