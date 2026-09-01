## One node of a recursive tag query: a boolean operator over a set of tags
## and, recursively, child expressions.
##
## ALL/ANY/NONE apply uniformly to the combined set of conditions this node
## holds - each of its own `tags` and each of its `expressions` is one
## condition, and the operator does not distinguish between them.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayTagQueryExpression extends Resource

enum Operator {
	ALL,
	ANY,
	NONE,
}

@export var operator: GameplayTagQueryExpression.Operator = Operator.ALL

## Each is a condition: the target must hold this tag or a descendant of it.
@export var tags: Array[StringName] = []

## Each is itself a condition, evaluated the same way, recursively.
@export var expressions: Array[GameplayTagQueryExpression] = []
