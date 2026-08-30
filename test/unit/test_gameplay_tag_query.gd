## GameplayTagQuery: arbitrarily nested boolean queries over a tag set.
##
## @meta_license: MIT
extends GutTest

const A: StringName = &"Status.A"
const B: StringName = &"Status.B"
const C: StringName = &"Status.C"
const D: StringName = &"Status.D"
const PARENT: StringName = &"Damage"
const CHILD: StringName = &"Damage.Fire"
const NOT_A_CHILD: StringName = &"Damages"


#region Builders
func _leaf(operator: GameplayTagQueryExpression.Operator, tags: Array[StringName]) -> GameplayTagQueryExpression:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = operator
	expression.tags = tags
	return expression


func _node(
	operator: GameplayTagQueryExpression.Operator, children: Array[GameplayTagQueryExpression]
) -> GameplayTagQueryExpression:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = operator
	expression.expressions = children
	return expression


func _query(root: GameplayTagQueryExpression) -> GameplayTagQuery:
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = root
	return query


func _runtime(tags: Array[StringName]) -> GameplayTagRuntime:
	var runtime: GameplayTagRuntime = GameplayTagRuntime.new()
	for tag: StringName in tags:
		runtime.add(tag)
	return runtime
#endregion


#region Hierarchical matching, through the shared primitive
func test_an_exact_tag_matches() -> void:
	var query: GameplayTagQuery = _query(_leaf(GameplayTagQueryExpression.Operator.ALL, [A]))
	assert_true(query.matches_tags([A]))


func test_a_descendant_tag_matches_its_ancestor() -> void:
	var query: GameplayTagQuery = _query(_leaf(GameplayTagQueryExpression.Operator.ALL, [PARENT]))
	assert_true(query.matches_tags([CHILD]))


func test_a_false_prefix_does_not_match() -> void:
	var query: GameplayTagQuery = _query(_leaf(GameplayTagQueryExpression.Operator.ALL, [PARENT]))
	assert_false(query.matches_tags([NOT_A_CHILD]))
#endregion


#region Operators
func test_all_requires_every_condition() -> void:
	var query: GameplayTagQuery = _query(_leaf(GameplayTagQueryExpression.Operator.ALL, [A, B]))
	assert_true(query.matches_tags([A, B]))
	assert_false(query.matches_tags([A]))


func test_any_requires_one_condition() -> void:
	var query: GameplayTagQuery = _query(_leaf(GameplayTagQueryExpression.Operator.ANY, [A, B]))
	assert_true(query.matches_tags([A]))
	assert_false(query.matches_tags([C]))


func test_none_requires_no_condition() -> void:
	var query: GameplayTagQuery = _query(_leaf(GameplayTagQueryExpression.Operator.NONE, [A, B]))
	assert_true(query.matches_tags([C]))
	assert_false(query.matches_tags([A]))


func test_a_nested_expression_combines_its_children() -> void:
	# (A AND B)
	var inner: GameplayTagQueryExpression = _leaf(GameplayTagQueryExpression.Operator.ALL, [A, B])
	var query: GameplayTagQuery = _query(_node(GameplayTagQueryExpression.Operator.ALL, [inner]))
	assert_true(query.matches_tags([A, B]))
	assert_false(query.matches_tags([A]))


func test_the_worked_formula() -> void:
	# ((A AND B) OR C) AND NOT D
	var a_and_b: GameplayTagQueryExpression = _leaf(GameplayTagQueryExpression.Operator.ALL, [A, B])
	var or_c: GameplayTagQueryExpression = _node(
		GameplayTagQueryExpression.Operator.ANY, [a_and_b]
	)
	or_c.tags = [C]
	var not_d: GameplayTagQueryExpression = _leaf(GameplayTagQueryExpression.Operator.NONE, [D])
	var root: GameplayTagQueryExpression = _node(
		GameplayTagQueryExpression.Operator.ALL, [or_c, not_d]
	)
	var query: GameplayTagQuery = _query(root)

	assert_true(query.matches_tags([A, B]), "A and B satisfy the OR")
	assert_true(query.matches_tags([C]), "C alone satisfies the OR")
	assert_false(query.matches_tags([A]), "A alone satisfies neither branch of the OR")
	assert_false(query.matches_tags([C, D]), "C satisfies the OR but D violates NOT D")
#endregion


#region Empty semantics
func test_an_empty_query_matches_anything() -> void:
	var query: GameplayTagQuery = GameplayTagQuery.new()
	assert_true(query.is_empty())
	assert_true(query.matches_tags([]))
	assert_true(query.matches_tags([A]))


func test_all_of_nothing_is_true() -> void:
	var no_tags: Array[StringName] = []
	var query: GameplayTagQuery = _query(_leaf(GameplayTagQueryExpression.Operator.ALL, no_tags))
	assert_true(query.matches_tags([]))


func test_any_of_nothing_is_false() -> void:
	var no_tags: Array[StringName] = []
	var query: GameplayTagQuery = _query(_leaf(GameplayTagQueryExpression.Operator.ANY, no_tags))
	assert_false(query.matches_tags([A]))


func test_none_of_nothing_is_true() -> void:
	var no_tags: Array[StringName] = []
	var query: GameplayTagQuery = _query(_leaf(GameplayTagQueryExpression.Operator.NONE, no_tags))
	assert_true(query.matches_tags([A]))
#endregion


#region Validation
func test_a_well_formed_query_validates() -> void:
	var query: GameplayTagQuery = _query(_leaf(GameplayTagQueryExpression.Operator.ALL, [A, B]))
	assert_true(query.validate().is_ok())


func test_an_empty_query_validates() -> void:
	assert_true(GameplayTagQuery.new().validate().is_ok())


func test_an_empty_tag_string_is_invalid() -> void:
	var query: GameplayTagQuery = _query(_leaf(GameplayTagQueryExpression.Operator.ALL, [&""]))
	var validation: GameplayTagQueryValidationResult = query.validate()
	assert_eq(validation.status, GameplayTagQueryValidationResult.Status.EMPTY_TAG)


func test_a_malformed_tag_is_invalid() -> void:
	var query: GameplayTagQuery = _query(
		_leaf(GameplayTagQueryExpression.Operator.ALL, [&"not valid!"])
	)
	var validation: GameplayTagQueryValidationResult = query.validate()
	assert_eq(validation.status, GameplayTagQueryValidationResult.Status.INVALID_TAG)
	assert_eq(validation.invalid_tag, &"not valid!")


func test_a_cyclic_expression_is_invalid_and_does_not_recurse_forever() -> void:
	var left: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	var right: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	left.expressions = [right]
	right.expressions = [left]
	var query: GameplayTagQuery = _query(left)

	var validation: GameplayTagQueryValidationResult = query.validate()
	assert_eq(validation.status, GameplayTagQueryValidationResult.Status.CYCLIC_EXPRESSION)
	# The same cycle, asked to match rather than validate, terminates too -
	# false rather than a stack overflow.
	assert_false(query.matches_tags([]))


func test_the_same_shared_child_reached_from_two_branches_is_not_a_cycle() -> void:
	var shared: GameplayTagQueryExpression = _leaf(GameplayTagQueryExpression.Operator.ALL, [A])
	var root: GameplayTagQueryExpression = _node(
		GameplayTagQueryExpression.Operator.ANY, [shared, shared]
	)
	var query: GameplayTagQuery = _query(root)
	assert_true(query.validate().is_ok(), "revisiting a sibling's own child is not a cycle")
	assert_true(query.matches_tags([A]))
#endregion


#region Runtime and Array agree, and evaluation does not mutate or drift
func test_matches_runtime_and_matches_tags_agree() -> void:
	var query: GameplayTagQuery = _query(_leaf(GameplayTagQueryExpression.Operator.ALL, [A, B]))
	var runtime: GameplayTagRuntime = _runtime([A, B])
	assert_eq(query.matches_runtime(runtime), query.matches_tags(runtime.active_tags()))


func test_evaluation_does_not_mutate_the_query_or_the_runtime() -> void:
	var expression: GameplayTagQueryExpression = _leaf(GameplayTagQueryExpression.Operator.ALL, [A])
	var query: GameplayTagQuery = _query(expression)
	var runtime: GameplayTagRuntime = _runtime([A])

	query.matches_runtime(runtime)

	assert_eq(expression.tags, [A] as Array[StringName], "the expression is unchanged")
	assert_eq(runtime.active_tags(), [A] as Array[StringName], "the runtime is unchanged")


func test_repeated_evaluation_is_deterministic() -> void:
	var query: GameplayTagQuery = _query(_leaf(GameplayTagQueryExpression.Operator.ALL, [A, B]))
	var first: bool = query.matches_tags([A, B])
	for _attempt: int in 5:
		assert_eq(query.matches_tags([A, B]), first)
#endregion
