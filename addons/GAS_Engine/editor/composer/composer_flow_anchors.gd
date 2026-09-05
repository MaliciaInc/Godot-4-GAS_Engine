## Holding on to which statement is which, across a transaction that moves them.
##
## A node's id is derived from the line it was read from, so the moment a
## transformation moves anything every id below it is a different id. A move is
## made of several transformations, and each one has to find the same statements
## the last one was talking about - which cannot be done with ids and must not be
## done with a name a person could have written twice.
##
## The answer is a comment nobody ever sees. Before the surgery each statement
## being touched gets a marked line of its own; the reread finds it by that mark;
## and the mark is taken out before anything is committed. It is not an identity
## the file keeps - the file keeps nothing about the graph - it is a piece of
## string tied round a statement for the length of one operation.
##
## The prefix is checked against the file first. If a person happens to have
## written that comment themselves, a numbered variant is used instead, chosen as
## the first free integer so the same file always produces the same anchors.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerFlowAnchors extends RefCounted

const PREFIX: String = "# @composer-transient-anchor "
const NEWLINE: String = "\n"
const TAB: String = "\t"

## How many spellings of the prefix to try before giving up. A file holding
## thirty-one different transient-anchor comments somebody typed by hand is not a
## file this needs to serve.
const MOST_SPELLINGS: int = 32


## An anchored copy of a file, and what each statement is called inside it.
class Anchored extends RefCounted:
	var source: String = ""

	## The original node id, to the mark now standing above that statement.
	var tokens: Dictionary[StringName, String] = {}

	## The spelling used, so the marks can be taken out again.
	var prefix: String = ComposerFlowAnchors.PREFIX

	func is_ok() -> bool:
		return not source.is_empty()

	## The mark that stands for `node_id`, or nothing.
	func token_of(node_id: StringName) -> String:
		return tokens.get(node_id, "")


## Put a mark above each of those statements, and say what each mark is.
##
## Above the statement itself and below whatever it carried in: a comment a
## person wrote belongs to their statement and stays where they put it, and the
## mark has to sit where the reread will read it as part of the same run.
static func anchor(
	source: String, graph: ComposerGraph, node_ids: Array[StringName]
) -> Anchored:
	var made: Anchored = Anchored.new()
	made.prefix = _free_prefix(source)
	if made.prefix.is_empty():
		return made

	var marks: Dictionary[int, String] = {}
	var number: int = 0
	for node_id: StringName in node_ids:
		var node: ComposerNode = graph.find_node(node_id)
		if node == null or not node.source_backed or node.source_text.is_empty():
			continue
		if made.tokens.has(node_id):
			continue
		var token: String = "%s%d" % [made.prefix, number]
		made.tokens[node_id] = token
		marks[node.span.last_line - node.source_text.size() + 1] = (
			TAB.repeat(maxi(node.indent, 1)) + token
		)
		number += 1

	var lines: PackedStringArray = source.split(NEWLINE)
	var written: PackedStringArray = PackedStringArray()
	for index: int in lines.size():
		if marks.has(index + 1):
			written.append(marks[index + 1])
		written.append(lines[index])
	made.source = NEWLINE.join(written)
	return made


## The statement carrying that mark, or nothing.
static func find_by_token(graph: ComposerGraph, token: String) -> ComposerNode:
	for node: ComposerNode in graph.nodes:
		if not node.source_backed:
			continue
		for line: String in node.carried:
			if line.strip_edges() == token:
				return node
	return null


## The same file without the marks, whichever spelling was used.
static func strip_anchors(source: String, prefix: String) -> String:
	var kept: PackedStringArray = PackedStringArray()
	for line: String in source.split(NEWLINE):
		if line.strip_edges().begins_with(prefix.strip_edges()):
			continue
		kept.append(line)
	return NEWLINE.join(kept)


## Whether any mark of that spelling is left in the file.
static func holds_anchors(source: String, prefix: String) -> bool:
	for line: String in source.split(NEWLINE):
		if line.strip_edges().begins_with(prefix.strip_edges()):
			return true
	return false


## A spelling this file does not already use, or nothing when there is none.
##
## Deterministic on purpose: the same file has to produce the same anchors every
## time, or a failure would be a different failure on the second run.
static func _free_prefix(source: String) -> String:
	if not source.contains(PREFIX.strip_edges()):
		return PREFIX
	for number: int in range(2, MOST_SPELLINGS):
		var spelled: String = "%s-%d " % [PREFIX.strip_edges(), number]
		if not source.contains(spelled.strip_edges()):
			return spelled
	return ""
