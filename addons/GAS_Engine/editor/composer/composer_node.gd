## One node of the projection: a statement of the ability, described.
##
## It holds no gameplay state and reaches nothing. It does not apply an effect,
## does not consult a tag, and has never heard of an AbilitySystemComponent. It
## is a description of text that has already been read, which is what lets the
## engine stay the only thing that runs.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerNode extends RefCounted

## What a diagnostic found here, if anything.
enum State { CLEAN, WARNING, ERROR }

## Which of the two connection families a port belongs to.
##
## Flow is horizontal, left to right, so execution and data arrive on the same
## sides. They are told apart by the shape drawn for them, never by position -
## splitting them across sides makes a graph that has to be read in two
## directions at once.
enum PortKind { EXECUTION, DATA }

enum PortDirection { INPUT, OUTPUT }

## Where a field's value comes from.
##
## MISSING is not an error state of LITERAL: it is a third thing, and the whole
## UI depends on the difference. A field showing `12.0` and an Output row saying
## "not connected" contradict each other; a field that reports MISSING says the
## same thing the diagnostic says, because both read this.
enum ValueSource { LITERAL, WIRED, MISSING }


## A named value on a node - what the Inspector edits and the card shows.
class Field extends RefCounted:
	var label: String = ""
	var type_name: StringName = &""
	var display: String = ""
	var source: ComposerNode.ValueSource = ComposerNode.ValueSource.LITERAL

	func is_satisfied() -> bool:
		return source != ComposerNode.ValueSource.MISSING


## A place a wire can attach. Always drawn, connected or not: a card with only
## its wired ports visible looks like a node that takes nothing.
class Port extends RefCounted:
	var id: StringName = &""
	var label: String = ""
	var type_name: StringName = &""
	var kind: ComposerNode.PortKind = ComposerNode.PortKind.DATA
	var direction: ComposerNode.PortDirection = ComposerNode.PortDirection.INPUT

	func is_execution() -> bool:
		return kind == ComposerNode.PortKind.EXECUTION


var id: StringName = &""

## Which entry of the catalog this is, and therefore which engine call it
## prints. A node with no type is a node the writer cannot emit.
var type_id: StringName = &""

var title: String = ""
var fields: Array[Field] = []
var ports: Array[Port] = []
var state: ComposerNode.State = ComposerNode.State.CLEAN

## Whether this node suspends the ability and waits.
##
## Every card is glass, so the treatment cannot carry this. The word `await` on
## the card does, which is the better signal anyway: a label is read, a texture
## is only felt.
var awaits: bool = false

## The lines this was read from. See ComposerSpan for why it is not optional.
var span: ComposerSpan = ComposerSpan.new()


func find_port(port_id: StringName) -> Port:
	for port: Port in ports:
		if port.id == port_id:
			return port
	return null


func find_field(label: String) -> Field:
	for field: Field in fields:
		if field.label == label:
			return field
	return null


## Whether every field this node needs has something in it.
##
## Asked rather than stored, so it cannot fall out of step with the fields it
## describes the moment one is edited.
func is_satisfied() -> bool:
	for field: Field in fields:
		if not field.is_satisfied():
			return false
	return true
