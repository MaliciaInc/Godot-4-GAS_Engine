## A recursive, arbitrarily nested boolean query over a set of gameplay tags -
## `((A AND B) OR C) AND NOT D`, expressed as nested
## GameplayTagQueryExpression nodes rather than a flat has/has_any/has_all
## check.
##
## Matching never mutates the query or the runtime it is asked about, and
## never recurses unboundedly: a cyclic graph of expressions - which nothing
## but a hand-wired or corrupted Resource graph could produce - is treated as
## satisfying nothing, the same answer `validate()` gives it as a definition.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayTagQuery extends Resource

@export var root: GameplayTagQueryExpression = null


## An empty query has no restriction: everything matches it.
func is_empty() -> bool:
	return root == null


## True against a live runtime's currently active tags.
func matches_runtime(runtime: GameplayTagRuntime) -> bool:
	if runtime == null:
		return is_empty()
	return matches_tags(runtime.active_tags())


## True against an arbitrary tag set - a runtime's own, or a hypothetical one
## a tool wants to preview.
func matches_tags(tags: Array[StringName]) -> bool:
	if is_empty():
		return true
	var visiting: Array[GameplayTagQueryExpression] = []
	return _matches(root, tags, visiting)


## Whether this is a legal definition: no empty or malformed tag, and no
## expression that is, directly or through its children, its own ancestor.
func validate() -> GameplayTagQueryValidationResult:
	var result: GameplayTagQueryValidationResult = GameplayTagQueryValidationResult.new()
	if is_empty():
		return result
	var visiting: Array[GameplayTagQueryExpression] = []
	_validate(root, visiting, result)
	return result


#region Matching
static func _matches(
	expression: GameplayTagQueryExpression,
	tags: Array[StringName],
	visiting: Array[GameplayTagQueryExpression]
) -> bool:
	if expression == null:
		return true
	# A node already on the current path is a cycle, not a legitimate shared
	# subexpression - those are only ever revisited from a sibling branch,
	# never while still inside their own evaluation.
	if visiting.has(expression):
		return false
	visiting.append(expression)

	var results: Array[bool] = []
	for tag: StringName in expression.tags:
		results.append(GameplayTagRuntime.tag_set_has(tags, tag))
	for child: GameplayTagQueryExpression in expression.expressions:
		results.append(_matches(child, tags, visiting))

	visiting.pop_back()
	return _combine(expression.operator, results)


## ALL([]) = true, ANY([]) = false, NONE([]) = true: a node with no
## conditions at all imposes no restriction under ALL or NONE, and satisfies
## none under ANY.
static func _combine(
	operator: GameplayTagQueryExpression.Operator, results: Array[bool]
) -> bool:
	match operator:
		GameplayTagQueryExpression.Operator.ALL:
			for result: bool in results:
				if not result:
					return false
			return true
		GameplayTagQueryExpression.Operator.ANY:
			for result: bool in results:
				if result:
					return true
			return false
		GameplayTagQueryExpression.Operator.NONE:
			for result: bool in results:
				if result:
					return false
			return true
	return false
#endregion


#region Validation
static func _validate(
	expression: GameplayTagQueryExpression,
	visiting: Array[GameplayTagQueryExpression],
	result: GameplayTagQueryValidationResult
) -> void:
	if expression == null or not result.is_ok():
		return
	if visiting.has(expression):
		result.status = GameplayTagQueryValidationResult.Status.CYCLIC_EXPRESSION
		return
	visiting.append(expression)

	for tag: StringName in expression.tags:
		if not result.is_ok():
			break
		if String(tag).is_empty():
			result.status = GameplayTagQueryValidationResult.Status.EMPTY_TAG
			break
		if not GameplayTagRegistry.is_valid_tag_string(String(tag)):
			result.status = GameplayTagQueryValidationResult.Status.INVALID_TAG
			result.invalid_tag = tag
			break

	for child: GameplayTagQueryExpression in expression.expressions:
		if not result.is_ok():
			break
		_validate(child, visiting, result)

	visiting.pop_back()
#endregion
