## The values a statement carries, read into fields a person can edit.
##
## Two kinds of statement carry values. A call carries its arguments, named and
## typed by the catalog where it knows the call. A structural statement carries
## exactly one: the condition an `if` tests, the value a `match` switches on,
## what a `return` hands back. Each becomes a field with the whole contract an
## argument has - a type, a default, whether the writer can put it back - so one
## editor serves all of them and the same door commits all of them.
##
## Built here rather than in the reader because the reader is about which line is
## which node, and this is about what a node holds. The two questions were one
## function for a while, and the function grew past the size this project keeps
## a file to.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerNodeFields extends RefCounted

## What the structural fields are called on a card.
const CONDITION: String = "Condition"
const VALUE: String = "Value"
const RETURN_VALUE: String = "Return Value"

## What an argument is called when the catalog does not know the call: its
## place in the list, which says "this is the second thing you passed" and
## claims nothing more.
const NUMBERED: String = "#%d"

const OPEN_BRACKET: String = "("
const SHUT_BRACKET: String = ")"


## The fields of `node`, whose statement `verdict` classified. `returns` is what
## the method declares it hands back, for a `return` to be typed by.
static func of(
	node: ComposerNode, verdict: ComposerSubset.Verdict, returns: StringName
) -> Array[ComposerNode.Field]:
	if not node.type_id.is_empty():
		return of_call(node.text, node.entry)
	return structural(node, verdict, returns)


#region A call's arguments
## One field per argument, named by the catalog where it knows the call.
##
## The label is the engine's own parameter name, read from the method rather
## than invented here. A call the catalog does not offer still draws - a person
## may write anything the subset admits - but its arguments fall back to their
## position.
static func of_call(text: String, entry: ComposerCatalog.Entry) -> Array[ComposerNode.Field]:
	var fields: Array[ComposerNode.Field] = []
	var open: int = text.find(OPEN_BRACKET)
	if open < 0 or not text.ends_with(SHUT_BRACKET):
		return fields

	var inside: String = text.substr(open + 1, text.length() - open - 2).strip_edges()
	if inside.is_empty():
		return fields

	var position: int = 0
	# Split on the call's own commas. Every comma would cut `build(x, y)` in
	# half and hand the card two arguments the file never passed.
	for argument: String in ComposerSubset.arguments_of(inside):
		var declared: ComposerNode.Field = (
			entry.parameter(position) if entry != null else null
		)
		var field: ComposerNode.Field = ComposerNode.Field.new()
		field.label = declared.label if declared != null else NUMBERED % (position + 1)
		field.type_name = declared.type_name if declared != null else &""
		# Everything else the engine said about this argument, carried onto the
		# read field rather than left in the catalog. A control is chosen from the
		# hint and an unplugged wire is replaced by the declared default, and both
		# of those happen to a node that was read out of a file - so a field that
		# knows only its type is a field neither of them can serve.
		if declared != null:
			declare(field, declared)
		field.display = argument.strip_edges()
		# A call is the one statement the writer rebuilds from its fields, so every
		# argument of one is something a person may change.
		field.editable = true
		fields.append(field)
		position += 1
	return fields


## Copy what reflection said about an argument onto the field read for it.
##
## The display is not copied: that is what the file passes, and it is the one
## thing here the person wrote rather than the engine.
##
## Public because a gap the validator reports is the same contract with
## nothing filled in yet, and a second copy of this list is a second place to
## forget a hint - which is a value editor that offers free text where the
## engine declared an enum.
static func declare(field: ComposerNode.Field, declared: ComposerNode.Field) -> void:
	field.variant_type = declared.variant_type
	field.class_id = declared.class_id
	field.hint = declared.hint
	field.hint_string = declared.hint_string
	field.usage = declared.usage
	field.default_expression = declared.default_expression
#endregion


#region What a structural statement carries
## The one value a branch, a switch or an end holds, or nothing for a statement
## that holds none.
##
## A `match` value is typed as Variant on purpose: the language compares
## anything, so narrowing it here would refuse a wire the file would accept.
static func structural(
	node: ComposerNode, verdict: ComposerSubset.Verdict, returns: StringName
) -> Array[ComposerNode.Field]:
	if node.projection_kind == ComposerNode.ProjectionKind.BRANCH:
		return [
			_field(
				CONDITION,
				ComposerTypes.BOOL,
				header_expression(node.text),
				ComposerTypes.default_expression(ComposerTypes.BOOL)
			)
		]
	if node.projection_kind == ComposerNode.ProjectionKind.SWITCH:
		return [
			_field(
				VALUE,
				ComposerTypes.VARIANT,
				header_expression(node.text),
				ComposerTypes.NOTHING
			)
		]
	if verdict.kind == ComposerSubset.Kind.RETURN:
		var handed_back: String = return_expression(node.text)
		# A bare `return` hands nothing back and gets no field. Growing one here
		# would let somebody write a value into a method that returns void.
		if handed_back.is_empty():
			return []
		return [
			_field(
				RETURN_VALUE, returns, handed_back, ComposerTypes.default_expression(returns)
			)
		]
	return []


## The expression a block header tests or switches on: `ready` in `if ready:`,
## `state` in `match state:`. The keyword and the colon are the line's; the
## expression is the person's.
static func header_expression(text: String) -> String:
	var head: String = code_of(text).strip_edges().trim_suffix(":")
	var space: int = head.find(" ")
	if space < 0:
		return ""
	return head.substr(space + 1).strip_edges()


## What a `return` hands back, or nothing for a bare one.
static func return_expression(text: String) -> String:
	var line: String = code_of(text).strip_edges()
	if not line.begins_with(ComposerSubset.RETURN_OPENER):
		return ""
	return line.substr(ComposerSubset.RETURN_OPENER.length()).strip_edges()


## The part of `line` that is code, without the comment trailing it.
##
## What a statement carries stops where the person's note starts. Read here
## and written back through here, so that editing a commented line puts the
## comment back instead of eating it - and so that a condition is `ready`
## rather than `ready: # for now`.
static func code_of(line: String) -> String:
	var mark: int = ComposerSubset.scan(line).comment
	return line if mark < 0 else line.substr(0, mark)


static func _field(
	label: String, type_name: StringName, display: String, default_expression: String
) -> ComposerNode.Field:
	var field: ComposerNode.Field = ComposerNode.Field.new()
	field.label = label
	field.type_name = type_name
	field.display = display
	field.default_expression = default_expression
	field.source = ComposerNode.ValueSource.LITERAL
	field.editable = true
	return field
#endregion
