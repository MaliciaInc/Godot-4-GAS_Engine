## One node of the projection: a statement of the ability, described.
##
## It holds no gameplay state and reaches nothing. It does not apply an effect,
## does not consult a tag, and has never heard of an AbilitySystemComponent. It
## is a description of text that has already been read, which is what lets the
## engine stay the only thing that runs.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
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

## What a node is a projection of.
##
## STATEMENT is the ordinary case: a line of the body. ENTRY is where the method
## begins and is not written anywhere. BRANCH and SWITCH fan execution out, so
## they carry more than one exec output. SUPPORT is a line the projection needs
## to read but nobody should be shown - an `else:` header has no card.
enum ProjectionKind {
	STATEMENT,
	ENTRY,
	BRANCH,
	SWITCH,
	SUPPORT,
}

## How many wires a port may hold at once.
##
## One value produced can feed many arguments, so a data output is MULTIPLE. Any
## input takes one, and execution leaves a statement by exactly one path per
## port, so everything else is SINGLE.
enum PortMultiplicity {
	SINGLE,
	MULTIPLE,
}

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

	## What reflection said about this argument, kept whole.
	##
	## A control cannot be chosen from the type name alone: an `int` with an enum
	## hint wants a dropdown of the names the engine declared, and the same `int`
	## without one wants a number. Throwing the hint away at read time and
	## guessing later is how a person ends up typing raw numbers into an enum.
	var variant_type: int = TYPE_NIL
	var class_id: StringName = &""
	var hint: int = PROPERTY_HINT_NONE
	var hint_string: String = ""
	var usage: int = PROPERTY_USAGE_DEFAULT

	## What Composer writes here when it creates this call, so a new statement
	## compiles instead of being born with an argument missing.
	var default_expression: String = ""

	## Whether the writer knows how to put a new value here.
	##
	## Decided where the field is built, because that is the one place that knows
	## what kind of statement it came from: an argument of a call the writer can
	## rebuild, the condition of a branch, the value a match switches on, what a
	## return hands back - all true. A field read out of a shape the writer has
	## no way to print again is false, whatever its type, and asking the node's
	## type instead was how a branch's condition could never be touched.
	var editable: bool = false

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
	var multiplicity: ComposerNode.PortMultiplicity = (
		ComposerNode.PortMultiplicity.SINGLE
	)

	## Which of the node's fields a data input stands for, or -1 for a pin that
	## stands for none.
	##
	## Carried on the pin rather than parsed out of its id. `arg_2` happens to end
	## in a number; `condition_in` does not, and a controller that read the index
	## off the name could reach a call's arguments and nothing else.
	var field_index: int = -1

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

## Which catalog call this statement is, or null when the catalog cannot be
## sure it is any of them.
##
## Decided once, by the reader, which is the only thing that can see the file
## the call was written in and the locals declared above it. Asking again later
## from somewhere with less of that in view is how two parts of the tool come to
## disagree about what a statement is.
var entry: ComposerCatalog.Entry = null

## Whether a person may change `field` at all.
##
## The field says so itself. It used to be decided from the statement - only a
## call had a type, so only a call's fields could be touched - which made the
## condition of a branch and the value a return hands back things a person could
## see and never change. Each field is now built knowing whether the writer can
## print it, and that is the whole answer.
##
## A value that arrives on a cable is **not** an exception, though it was for a
## while. The reasoning was that a cable cannot be typed over - but the text is
## the truth here and the cable is read out of it, so naming a different local
## is rewiring and writing a literal is disconnecting. What changes for a wired
## value is what it is offered as, not whether it may move.
func may_edit(field: Field) -> bool:
	return field != null and field.editable


## Whether arbitrary text belongs in it, or a choice of what feeds it.
func may_type(field: Field) -> bool:
	return may_edit(field) and field.source != ComposerNode.ValueSource.WIRED


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

## What this node is a projection of, and whether it is written down at all.
##
## Entry is the one node with no line behind it: `source_backed` false says the
## writer must never look for it in the file. A support header - the `else:` of
## a branch - is the opposite: it is in the file and must not be drawn.
var projection_kind: ComposerNode.ProjectionKind = ComposerNode.ProjectionKind.STATEMENT
var source_backed: bool = true
var visible_in_graph: bool = true

## Whether execution stops here. A terminal node never grows an exec output.
var terminal: bool = false


## Optional visual placement written as a reserved comment immediately before
## this statement. Execution still comes from source order; this value is only
## where the projection is drawn.
var has_layout_position: bool = false
var layout_position: Vector2 = Vector2.ZERO


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


## Which field a pin stands for, or -1 when it stands for none.
##
## The pin was given this when it was read, so asking it is one lookup and it
## works for every pin there is. Parsing a number off the end of the id was the
## older way, and it can only ever answer for an argument - a condition, a match
## value and a return value are all named rather than numbered.
func field_for(port_id: StringName) -> int:
	var pin: Port = find_port(port_id)
	return pin.field_index if pin != null else -1


## The pin that stands for the field at `index`, or nothing.
##
## The other direction of `field_for()`. A panel that lists arguments knows a
## position and needs the pin; a canvas that was dragged knows the pin and
## needs the position. Both are answered from what the reader wrote on the pin,
## so neither has to know that an argument's id carries a number and a
## condition's does not.
func pin_for_field(index: int) -> Port:
	for pin: Port in ports:
		if pin.field_index == index and not pin.is_execution():
			return pin
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
