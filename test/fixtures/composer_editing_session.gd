## An ability open in front of a controller, the way a test needs one.
##
## Opening a document, binding a controller to it and then finding the statements
## again by what they say is the arrangement of every test about editing. Kept in
## one place because the finding is the part with an opinion in it: a node's id is
## derived from the line it was read from, so it moves whenever anything above it
## does, and a test that reached for ids would be testing line numbers.
##
## Nothing here asserts. A fixture that judged would be a second set of rules to
## keep in step with the real ones.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerEditingSession extends RefCounted

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"

var document: ComposerDocument = null
var controller: ComposerConnectionController = null


## An ability whose body is those statements, with a controller on it.
##
## `document` is passed in rather than made here so a test can hand over one
## that behaves differently - a document that refuses every commit, say - and
## get the same arrangement around it.
static func opened(
	statements: Array, on: ComposerDocument = null
) -> ComposerEditingSession:
	var made: ComposerEditingSession = ComposerEditingSession.new()
	made.document = on if on != null else ComposerDocument.new()
	made.document.open(script_of(statements), PATH)
	made.controller = ComposerConnectionController.new()
	made.controller.bind(made.document)
	return made


## An ability file whose body is those statements, one per line.
static func script_of(statements: Array) -> String:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	return HEAD + body


## The statement whose line contains `written`.
func node(written: String) -> ComposerNode:
	for found: ComposerNode in ComposerProjection.statements(document.graph()):
		if found.text.contains(written):
			return found
	return null


## "this statement runs after that one", as a connection.
func run_after(before: String, after: String) -> ComposerGraph.Connection:
	return ComposerReader.wire(
		node(before).id, ComposerReader.EXEC_OUT, node(after).id, ComposerReader.EXEC_IN
	)


## "the local this statement declares goes into that value of that one".
##
## The pin is asked for rather than spelled: `slot` is a field position, and
## the pin standing for one is called `argument_2` on a call and `condition_in`
## on a branch.
func value_into(producer: String, consumer: String, slot: int) -> ComposerGraph.Connection:
	var into: ComposerNode = node(consumer)
	var pin: ComposerNode.Port = into.pin_for_field(slot)
	return ComposerReader.wire(
		node(producer).id,
		ComposerReader.VALUE_OUT,
		into.id,
		pin.id if pin != null else &""
	)


## The one line of the body containing `written`, as it stands now.
func line(written: String) -> String:
	for found: String in document.printed().split("\n"):
		if found.contains(written):
			return found.strip_edges()
	return ""


## What the file says, and how many steps back there are.
func printed() -> String:
	return document.printed()


func depth() -> int:
	return document.history().depth()


func cables() -> int:
	return document.graph().data_connections().size()
