## A projection shaped like a real ability, for exercising the view.
##
## Lives in the fixtures rather than in the addon on purpose. Until the reader
## exists the Composer has nothing to draw, and shipping a canned graph inside
## the product to cover that up would put a second source of nodes beside the
## one that is supposed to be the only one.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerSampleGraph extends RefCounted

const EXEC_IN: StringName = &"exec_in"
const EXEC_OUT: StringName = &"exec_out"
const DATA_OUT: StringName = &"value_out"

const COMMIT: StringName = &"commit"
const APPLY: StringName = &"apply"
const WAIT: StringName = &"wait"
const CUE: StringName = &"cue"


## Commit, then a wait feeding a cue, with an effect applied along the way.
##
## Deliberately not a straight line: a branch and a join are what make the
## layout do something worth looking at, and the missing field is what makes the
## card and the Output panel agree about the same thing.
static func build() -> ComposerGraph:
	var graph: ComposerGraph = ComposerGraph.new()
	graph.source_path = "res://abilities/sample.gd"
	graph.nodes = [
		_node(COMMIT, &"gas.commit", "Commit Ability", ComposerSpan.new(12, 12), []),
		_node(APPLY, &"gas.apply_effect", "Apply Gameplay Effect", ComposerSpan.new(14, 17), [
			_field("Effect", "Burning"), _field("Level", "1.0"),
		]),
		_node(WAIT, &"gas.wait_target_data", "Wait Target Data", ComposerSpan.new(19, 21), [
			_field("Confirm", "Instant"),
		]),
		_node(CUE, &"gas.execute_cue", "Execute Cue", ComposerSpan.new(23, 26), [
			_field("Cue Tag", "Cue.Fire.Impact"), _missing("Magnitude"),
		]),
	] as Array[ComposerNode]

	graph.find_node(WAIT).awaits = true
	graph.find_node(CUE).state = ComposerNode.State.WARNING

	graph.connections = [
		ComposerReader.wire(COMMIT, EXEC_OUT, APPLY, EXEC_IN),
		ComposerReader.wire(APPLY, EXEC_OUT, WAIT, EXEC_IN),
		ComposerReader.wire(WAIT, EXEC_OUT, CUE, EXEC_IN),
	] as Array[ComposerGraph.Connection]

	var found: ComposerGraph.Diagnostic = ComposerGraph.Diagnostic.new()
	found.severity = ComposerGraph.Severity.WARNING
	found.message = "Execute Cue - Magnitude not connected"
	found.node_id = CUE
	found.span = ComposerSpan.new(25, 25)
	graph.diagnostics = [found] as Array[ComposerGraph.Diagnostic]
	return graph


## Takes a span rather than a pair of line numbers: two ints that must be read
## together are one value, and passing them apart is also one parameter over the
## budget this project keeps.
static func _node(
	id: StringName, type_id: StringName, title: String,
	span: ComposerSpan, fields: Array
) -> ComposerNode:
	var node: ComposerNode = ComposerNode.new()
	node.id = id
	node.type_id = type_id
	node.title = title
	node.span = span
	node.fields.assign(fields)
	node.ports = [
		ComposerReader.port(EXEC_IN, ComposerNode.PortKind.EXECUTION, ComposerNode.PortDirection.INPUT),
		ComposerReader.port(EXEC_OUT, ComposerNode.PortKind.EXECUTION, ComposerNode.PortDirection.OUTPUT),
		ComposerReader.port(DATA_OUT, ComposerNode.PortKind.DATA, ComposerNode.PortDirection.OUTPUT),
	] as Array[ComposerNode.Port]
	return node


static func _field(label: String, display: String) -> ComposerNode.Field:
	var field: ComposerNode.Field = ComposerNode.Field.new()
	field.label = label
	field.display = display
	return field


static func _missing(label: String) -> ComposerNode.Field:
	var field: ComposerNode.Field = ComposerNode.Field.new()
	field.label = label
	field.source = ComposerNode.ValueSource.MISSING
	return field
