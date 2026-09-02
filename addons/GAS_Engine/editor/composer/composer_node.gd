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

## The exact text those lines held.
##
## Not a second copy of the ability: it is the file's own text, held for as long
## as the file is open and written nowhere. It is what lets an untouched node be
## reprinted verbatim instead of rebuilt from this model - so a save can only
## change what someone actually edited, and every comment, space and choice of
## wording in the rest survives untouched.
var source_text: PackedStringArray = PackedStringArray()

## The comments and blank lines that came before the statement.
##
## Held apart from the statement because they are never rebuilt - nothing in the
## model stands for a comment, so anything that reprinted a node from the model
## alone would drop them. That is how a save deletes the note somebody wrote
## above the line they just edited, and they would find out much later.
var carried: PackedStringArray = PackedStringArray()

## Everything the statement says before the call: `var found: Node2D = ` in
## `var found: Node2D = pick_target()`, empty for a statement that is only a
## call.
##
## Kept because a rebuilt statement is a call plus whatever led up to it, and a
## writer that knew only the call printed `pick_target()` over the top of a
## person's local - the declaration, its name and its written type gone, and the
## lines below it now naming something that no longer exists.
var prefix: String = ""

## What the call is on: `owner_asc` in `owner_asc.add_tag(burning)`, empty for
## a call written bare.
##
## Kept apart from `type_id` so the id is the method - the same thing the
## catalog is keyed by - while a save still prints back the receiver the person
## wrote. Folding the two together made every call on the ability system a node
## the catalog had never heard of, which is most of the calls there are.
var receiver: String = ""

## The same statement as one line, with the wrapping taken out.
##
## A person wraps a long call across three lines and means one statement. The
## file keeps the three; everything that asks what this node *says* - which call
## it is, which argument names a local - asks this. Reading the last physical
## line instead sees `)` and concludes the statement is nothing.
var text: String = ""

## How deep this statement sits. Branch depth, and the indentation to reprint at.
var indent: int = 0

## Whether this node has been edited since it was read.
##
## Only a dirty node is rebuilt from the model. A clean one goes back exactly as
## it came, which is the difference between a tool that formats your file on
## every save and one that does not.
var dirty: bool = false


## How loudly this node's state speaks, in the vocabulary the diagnostics use.
##
## Declared here because this is where `State` lives, and read by the theme so
## a card's dot and its Output row cannot end up different colours for the same
## fact.
static func severity_of(state: ComposerNode.State) -> ComposerGraph.Severity:
	match state:
		State.WARNING:
			return ComposerGraph.Severity.WARNING
		State.ERROR:
			return ComposerGraph.Severity.ERROR
		_:
			return ComposerGraph.Severity.NOTE


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
