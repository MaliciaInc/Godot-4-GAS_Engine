## What GraphEdit is told about pins, so a drag can be refused before it lands.
##
## GraphEdit knows one thing about a pin: an integer. It will not let a wire be
## dropped between two integers it was not told about, which is what makes an
## impossible connection feel impossible - the cable does not snap, and nobody
## has to read a message explaining why what they just did was wrong.
##
## The numbers mean nothing outside the canvas. They are worked out fresh from
## whatever types the open ability happens to use, they never reach the file,
## and a different ability gets a different set. What they must be is *stable*
## for one graph: a pin that is 103 while a wire is being dragged and 104 when
## it lands is a pin the drop is refused on.
##
## This is not where a connection is decided. GraphEdit is a convenience that
## makes the common refusal instant; every wire that does land is checked again
## by the controller against `ComposerTypes`, because a widget's idea of what
## fits is not a rule about somebody's source code.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerPortTypes extends RefCounted

## Execution is always this, in every ability. It is one thing rather than a
## family, so it does not need a number worked out for it - and pinning it means
## a canvas rebuilt mid-drag cannot renumber the run of control underneath it.
const EXECUTION_TYPE: int = 1

## Where the value types start. Clear of the execution number with room between,
## so a stray off-by-one lands on nothing rather than on a run of control.
const DATA_BASE: int = 100

## Which family a written type name belongs to.
##
## Read by name, because a name is what a port carries: the reader takes the
## type off the line the person wrote. What each family looks like belongs to
## the palette rather than here - one place decides how this editor is coloured,
## and a second opinion about it is a second thing to keep in step.
const FAMILIES: Dictionary[StringName, Color] = {
	ComposerTypes.BOOL: ComposerTheme.PORT_BOOL,
	ComposerTypes.INT: ComposerTheme.PORT_INT,
	ComposerTypes.FLOAT: ComposerTheme.PORT_FLOAT,
	ComposerTypes.STRING: ComposerTheme.PORT_TEXT,
	ComposerTypes.STRING_NAME: ComposerTheme.PORT_TEXT,
	ComposerTypes.NODE_PATH: ComposerTheme.PORT_PATH,
	ComposerTypes.VECTOR2: ComposerTheme.PORT_VECTOR,
	ComposerTypes.VECTOR2I: ComposerTheme.PORT_VECTOR,
	ComposerTypes.VECTOR3: ComposerTheme.PORT_VECTOR,
	ComposerTypes.VECTOR3I: ComposerTheme.PORT_VECTOR,
	ComposerTypes.VECTOR4: ComposerTheme.PORT_VECTOR,
	ComposerTypes.VECTOR4I: ComposerTheme.PORT_VECTOR,
	ComposerTypes.COLOR: ComposerTheme.PORT_COLOUR,
}

var _numbers: Dictionary[StringName, int] = {}
var _registered: Array[Vector2i] = []


#region Numbering
## Work out a number for every value type this graph uses.
##
## Sorted by name before numbering, so the same ability always produces the same
## numbers however the nodes happened to be read. Without that, a rebuild
## triggered by an edit could hand a pin a different number than the one the
## drag started on, and the drop would be refused for no reason anybody could
## see.
func rebuild(graph: ComposerGraph) -> void:
	_numbers.clear()
	if graph == null:
		return

	var seen: Array[StringName] = []
	for node: ComposerNode in graph.visible_nodes():
		for pin: ComposerNode.Port in node.ports:
			if pin.is_execution() or seen.has(pin.type_name):
				continue
			seen.append(pin.type_name)
	seen.sort()

	for position: int in seen.size():
		_numbers[seen[position]] = DATA_BASE + position


## The number a pin of this type and family is drawn with.
##
## A type the graph did not have when it was last numbered answers `DATA_BASE`
## rather than nothing: an unnumbered pin would be one GraphEdit refuses every
## wire to, which reads to a person as a broken canvas rather than as a stale
## one.
func ui_type(type_name: StringName, kind: ComposerNode.PortKind) -> int:
	if kind == ComposerNode.PortKind.EXECUTION:
		return EXECUTION_TYPE
	if not _numbers.has(type_name):
		return DATA_BASE
	return _numbers[type_name]
#endregion


#region Telling GraphEdit
## Register every pair of numbers a wire may be dropped between.
##
## Rebuilt from nothing each time rather than added to. The pairs are derived
## from the ability that is open, so pairs left over from the last one would let
## somebody drop a wire between two types this ability never mentions.
func register_into(edit: GraphEdit, graph: ComposerGraph) -> void:
	for pair: Vector2i in _registered:
		edit.remove_valid_connection_type(pair.x, pair.y)
	_registered.clear()

	rebuild(graph)
	_allow(edit, EXECUTION_TYPE, EXECUTION_TYPE)
	for source: StringName in _numbers:
		for target: StringName in _numbers:
			# Asked of `ComposerTypes` rather than decided here. Two answers to
			# "does this fit" is one answer too many, and the one that would be
			# wrong is the one nobody checks against a file.
			if ComposerTypes.accepts(target, source):
				_allow(edit, _numbers[source], _numbers[target])


func _allow(edit: GraphEdit, from: int, to: int) -> void:
	edit.add_valid_connection_type(from, to)
	_registered.append(Vector2i(from, to))
#endregion


#region Drawing
## The colour a pin of this type is drawn in.
func color_for(type_name: StringName, kind: ComposerNode.PortKind) -> Color:
	if kind == ComposerNode.PortKind.EXECUTION:
		return ComposerTheme.PORT_EXECUTION
	if FAMILIES.has(type_name):
		return FAMILIES[type_name]
	if ComposerTypes.UNTYPED.has(type_name):
		return ComposerTheme.PORT_UNTYPED
	# Everything else is a class - the engine's own, the game's, a Resource. One
	# colour for all of them on purpose: the useful distinction on a canvas is
	# "this carries a thing" against "this carries a number", and splitting the
	# things apart by ancestry would need a colour per game.
	return ComposerTheme.PORT_OBJECT
#endregion
