## Every change somebody can make to a tag query, and every line the editor
## shows them - as operations and rows rather than as widgets.
##
## The thinking half of the query editor. Godot refuses to build an
## EditorProperty outside the editor, so a rule living in one is a rule nothing
## can check - and "what does adding a nested ANY under this ALL do" is exactly
## the kind of rule worth checking.
##
## Every operation works on the expression tree the runtime reads. There is no
## intermediate model: a query somebody edited is the query the engine
## evaluates, which is what makes the editor's preview mean anything.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTagQueryEdits extends RefCounted

## What each operator is called on screen, in the enum's own order.
const OPERATOR_NAMES: Array[String] = ["ALL", "ANY", "NONE"]

## The operator names as one string, which is the shape a Tree's range cell
## wants its choices in.
const OPERATOR_CHOICES: String = "ALL,ANY,NONE"

const NO_TAG: StringName = &""


## One line of the editor: an expression, or one tag belonging to one.
##
## A tag is a row of its own rather than a label on its parent because it is
## removable on its own - and because a leaf's picker has to know which
## expression it is picking for, which a row carries and a label would not.
class Row extends RefCounted:
	## The expression this row is, or the one the tag belongs to.
	var expression: GameplayTagQueryExpression = null

	## The tag, when this row is one. Empty when the row is an expression.
	var tag: StringName = GameplayTagQueryEdits.NO_TAG

	## How far in this row sits, counting the root as zero.
	var depth: int = 0

	func is_a_tag() -> bool:
		return tag != GameplayTagQueryEdits.NO_TAG

	## What the row reads as: the tag, or the operator's name.
	func shown() -> String:
		if is_a_tag():
			return String(tag)
		return GameplayTagQueryEdits.named(expression.operator)


## What one operator is called.
static func named(operator: GameplayTagQueryExpression.Operator) -> String:
	var index: int = int(operator)
	if index < 0 or index >= OPERATOR_NAMES.size():
		return OPERATOR_NAMES[0]
	return OPERATOR_NAMES[index]


## Give a query a root, if it has none.
##
## ALL by default, because a query with nothing in it satisfies everything and
## one somebody has just started building should say the ordinary thing rather
## than the one that never matches.
static func ensure_root(query: GameplayTagQuery) -> GameplayTagQueryExpression:
	if query == null:
		return null
	if query.root == null:
		query.root = GameplayTagQueryExpression.new()
	return query.root


## Add a nested expression under one that is already there.
##
## Nesting is the whole point of the three operators: "any of these, and none of
## those" is an ALL over an ANY and a NONE, and it cannot be said in one flat
## list however many tags it holds.
static func nest(
	under: GameplayTagQueryExpression,
	operator: GameplayTagQueryExpression.Operator = GameplayTagQueryExpression.Operator.ANY
) -> GameplayTagQueryExpression:
	if under == null:
		return null
	var made: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	made.operator = operator
	under.expressions.append(made)
	return made


## Take one nested expression out, and everything under it with it.
##
## False for an index that names nothing, so a caller acting on a stale row
## learns rather than removing whatever moved into that place.
static func unnest(from: GameplayTagQueryExpression, index: int) -> bool:
	if from == null or index < 0 or index >= from.expressions.size():
		return false
	from.expressions.remove_at(index)
	return true


## Take one nested expression out by identity rather than by position.
##
## What a row click actually knows: the tree the editor draws is rebuilt
## whenever anything changes, and an index read off a row that was drawn before
## the last edit points at whichever sibling has since moved into it.
static func drop(
	from: GameplayTagQueryExpression, expression: GameplayTagQueryExpression
) -> bool:
	if from == null or expression == null:
		return false
	return unnest(from, from.expressions.find(expression))


## Put a tag on one expression, unless it is already there.
##
## Twice is not twice as true, and a leaf that listed one tag two times would
## read as a longer condition than it is.
static func add_tag(to: GameplayTagQueryExpression, tag: StringName) -> bool:
	if to == null or tag == NO_TAG or to.tags.has(tag):
		return false
	to.tags.append(tag)
	return true


static func remove_tag(from: GameplayTagQueryExpression, tag: StringName) -> bool:
	if from == null or not from.tags.has(tag):
		return false
	from.tags.erase(tag)
	return true


## Change what an expression means without touching what is under it.
##
## An author who built "any of these five" and then decided they meant "all of
## these five" is changing one word, and an editor that made them rebuild the
## list would be an editor they edit around.
static func set_operator(
	on: GameplayTagQueryExpression, operator: GameplayTagQueryExpression.Operator
) -> bool:
	if on == null:
		return false
	on.operator = operator
	return true


## Every line the editor draws, in the order it draws them.
##
## Depth-first, an expression before what is under it, its own tags before its
## nested expressions - so a row's indentation is the nesting the runtime
## evaluates rather than an order the screen invented.
##
## An expression already on the path is a cycle, which is a corrupted definition
## the runtime already refuses to evaluate. Listed once and not descended into,
## so the author can see the row that is wrong and delete it: an editor that
## hung on the file it was asked to repair would be no help at all.
static func rows_of(query: GameplayTagQuery) -> Array[Row]:
	var rows: Array[Row] = []
	if query == null or query.root == null:
		return rows
	var visiting: Array[GameplayTagQueryExpression] = []
	_rows_under(query.root, 0, visiting, rows)
	return rows


static func _rows_under(
	expression: GameplayTagQueryExpression,
	depth: int,
	visiting: Array[GameplayTagQueryExpression],
	rows: Array[Row]
) -> void:
	if expression == null:
		return
	var row: Row = Row.new()
	row.expression = expression
	row.depth = depth
	rows.append(row)

	if visiting.has(expression):
		return
	visiting.append(expression)

	for tag: StringName in expression.tags:
		var leaf: Row = Row.new()
		leaf.expression = expression
		leaf.tag = tag
		leaf.depth = depth + 1
		rows.append(leaf)

	for nested: GameplayTagQueryExpression in expression.expressions:
		_rows_under(nested, depth + 1, visiting, rows)

	visiting.pop_back()


## How deep the tree goes, for a screen deciding how far to indent.
##
## Guarded against a cycle by the depth it is measuring: a query whose
## expressions reach back into themselves is a corrupted definition, and the
## runtime already refuses to evaluate one. This counts to the limit and stops
## rather than recursing forever alongside it.
static func depth_of(expression: GameplayTagQueryExpression, limit: int = 64) -> int:
	if expression == null or limit <= 0:
		return 0
	var deepest: int = 0
	for nested: GameplayTagQueryExpression in expression.expressions:
		deepest = maxi(deepest, depth_of(nested, limit - 1))
	return deepest + 1
