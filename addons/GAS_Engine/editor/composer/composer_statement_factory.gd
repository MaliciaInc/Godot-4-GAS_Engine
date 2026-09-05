## The one place a statement Composer creates is written.
##
## There used to be two ideas of what a new call looks like - the writer's and
## whatever a caller assembled - and they disagreed about arguments: the writer
## produced `wait_delay()`, which does not compile, because it had no opinion
## about what goes inside the brackets. It has one now, and it is the only one.
##
## Every declared argument is written, with the method's own default where it
## declares one and the type's zero where it does not. A person who asks for a
## node gets a line that runs; filling it in is editing, not repair.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerStatementFactory extends RefCounted

const TAB: String = "\t"
const AWAIT_MARK: String = "await "
const RESULT_SUFFIX: String = "_result"
const ARGUMENT_JOIN: String = ", "


## A call statement, ready to be a line of a body.
## Named `call_statement` rather than `call`: a static called `call` is hidden by
## `Object.call()`, which every RefCounted inherits, and the reference does not
## resolve.
static func call_statement(entry: ComposerCatalog.Entry, path: String) -> String:
	if entry == null:
		return ""
	return TAB + _invocation(entry, path)


## The same call, keeping what it returns in a new local.
##
## Only where there is something to keep and nothing to wait for: a name bound
## to an awaited call would need the `await` inside the declaration, which the
## subset does not read back, so the projection would lose the statement it just
## wrote.
static func local_call(
	entry: ComposerCatalog.Entry, path: String, used_names: PackedStringArray
) -> String:
	if entry == null or not ComposerTypes.is_a_value(entry.result_type) or entry.awaits:
		return ""
	return "%svar %s: %s = %s" % [
		TAB,
		unique_local_name(entry, used_names),
		entry.result_type,
		_invocation(entry, path),
	]


## Every declared argument, in order, with nothing left out.
##
## Optional arguments are written too. Leaving them off would be legal GDScript
## and would make the card and the file disagree about how many values this call
## has - and the card is where somebody edits them.
static func arguments(entry: ComposerCatalog.Entry) -> PackedStringArray:
	var written: PackedStringArray = PackedStringArray()
	if entry == null:
		return written
	for field: ComposerNode.Field in entry.parameters:
		if not field.default_expression.is_empty():
			written.append(field.default_expression)
			continue
		written.append(
			ComposerTypes.default_expression(field.type_name, field.variant_type)
		)
	return written


## A name for the result that nothing in the method is already using.
##
## Numbered rather than made unusual, because the person reading it should be
## able to tell at a glance that it is the second of the same thing.
static func unique_local_name(
	entry: ComposerCatalog.Entry, used_names: PackedStringArray
) -> String:
	if entry == null:
		return ""
	var base: String = String(entry.type_id) + RESULT_SUFFIX
	if not used_names.has(base):
		return base
	var attempt: int = 2
	while used_names.has("%s_%d" % [base, attempt]):
		attempt += 1
	return "%s_%d" % [base, attempt]


## `receiver.method(args)`, awaited where the entry says it suspends.
static func _invocation(entry: ComposerCatalog.Entry, path: String) -> String:
	var receiver: String = ComposerTypes.name_reaching(entry.source, path)
	var written: String = String(entry.type_id)
	if not receiver.is_empty():
		written = "%s.%s" % [receiver, written]
	var made: String = "%s(%s)" % [
		written, ARGUMENT_JOIN.join(arguments(entry))
	]
	return AWAIT_MARK + made if entry.awaits else made
