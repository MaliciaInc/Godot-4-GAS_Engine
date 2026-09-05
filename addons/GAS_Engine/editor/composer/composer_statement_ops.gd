## What can be done to the statements somebody has selected.
##
## Remove, repeat, copy, paste, and put a new call in. All five are the same
## shape - take the selection, work out which lines it covers, hand the document
## a change - and all five used to live in the screen beside the panel wiring,
## where the shape was repeated rather than stated.
##
## The selection arrives as an argument rather than being reached for. This
## knows the document and nothing about the canvas, so there is no path from an
## edit back to the thing that drew it, and a test can ask for any of these
## without a canvas existing at all.
##
## Nothing here decides what happens next. Each returns what the document said,
## and the caller redraws - because only the caller knows what else is on screen.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerStatementOps extends RefCounted

var _document: ComposerDocument = null


func bind(document: ComposerDocument) -> void:
	_document = document


## The lines those nodes cover, in the order the file has them.
##
## In the file's order rather than the selection's: a person picks cards in
## whatever order they click, and copying three statements has to hand back the
## three in the order they run.
func spans_of(picked: Array[StringName]) -> Array[ComposerSpan]:
	var found: Array[ComposerSpan] = []
	if _document == null or not _document.is_open():
		return found
	for id: StringName in picked:
		var node: ComposerNode = _document.graph().find_node(id)
		if node != null:
			found.append(node.span)
	# Sorted here rather than trusted from the caller. It happened to arrive in
	# order because the canvas reads its cards in the graph's order, which is a
	# coincidence two classes away from anything that says so - and every one of
	# these operations works on lines, so a copy taken bottom-up would paste
	# somebody's ability back inside out.
	found.sort_custom(
		func _by_line(one: ComposerSpan, other: ComposerSpan) -> bool:
			return one.first_line < other.first_line
	)
	return found


## Take those statements out. Nothing selected is nothing to do, not a refusal.
func remove(picked: Array[StringName]) -> ComposerGraph.Diagnostic:
	var spans: Array[ComposerSpan] = spans_of(picked)
	return _document.remove(spans) if not spans.is_empty() else null


func repeat(picked: Array[StringName]) -> ComposerGraph.Diagnostic:
	var spans: Array[ComposerSpan] = spans_of(picked)
	return _document.repeat(spans) if not spans.is_empty() else null


## The picked statements, as the text they are.
##
## Returned rather than put anywhere. A statement is GDScript and somebody who
## copies one should be able to paste it into the script editor beside this one,
## but where it goes is the caller's business - and asking this a question must
## not need a clipboard to exist.
func copy(picked: Array[StringName]) -> String:
	var spans: Array[ComposerSpan] = spans_of(picked)
	return _document.copy(spans) if not spans.is_empty() else ""


## Put text in after the selection.
##
## Anything at all may be on a clipboard, so what comes off one goes through the
## same door every other edit does and is read back before it is accepted.
func paste(picked: Array[StringName], written: String) -> ComposerGraph.Diagnostic:
	if _document == null or not _document.is_open() or written.strip_edges().is_empty():
		return null
	return _document.insert(written, _document.after(spans_of(picked)))


## A call chosen from the palette becomes a statement in the body.
func insert_call(picked: Array[StringName], key: StringName) -> ComposerGraph.Diagnostic:
	if _document == null or not _document.may_write():
		return null
	var written: String = ComposerWriter.call_for(
		ComposerCatalog.find(key), _document.path()
	)
	if written.is_empty():
		return null
	return _document.insert(written, _document.after(spans_of(picked)))
