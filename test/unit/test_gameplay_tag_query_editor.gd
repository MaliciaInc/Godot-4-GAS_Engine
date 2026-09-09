## Building `((A and B) or C) and not D` by clicking, and asking it about
## something that is not a character.
##
## Authoring a nested query in the default inspector means creating a
## GameplayTagQueryExpression, opening it, creating two more inside it, and
## typing the tags - with nothing on screen saying what the whole thing asks.
## The editor draws the tree instead. Nothing here builds the widget: Godot
## refuses to instantiate an EditorProperty outside the editor, so every
## decision it makes lives in GameplayTagQueryEdits, which is what these
## exercise.
##
## The second half is the duck interface. A door that is Locked, a region that
## is Indoors and a piece of cover that is Waist High all have tags and none of
## them wants an AbilitySystemComponent; a query that could only see tags
## through one would read all of them as untagged.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const InspectorPlugin = preload(
	"res://addons/GAS_Engine/gameplay_tag/gameplay_tag_query_inspector_plugin.gd"
)

const A: StringName = &"Status.Burning"
const B: StringName = &"Status.Bleeding"
const C: StringName = &"Status.Poisoned"
const D: StringName = &"Status.Immune"


## Something with tags and no ability system - the case the duck interface
## exists for.
class ADoor extends Node:
	var says: Array[StringName] = []

	func get_owned_gameplay_tags() -> Array[StringName]:
		return says


## Something with tags and no opinion of its own, which is most of a scene.
class AWall extends Node:
	pass


#region Building a nested query
## The three operators nested, and the query that comes out means what the
## nesting says.
##
## `((A and B) or C) and not D`: an ALL holding an ANY - which holds an ALL and
## the bare tag C - and a NONE. Built the way the editor builds it, one call per
## click, and then asked about tag sets that differ in exactly one thing.
func _built() -> GameplayTagQuery:
	var query: GameplayTagQuery = GameplayTagQuery.new()
	var root: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(query)

	var either: GameplayTagQueryExpression = GameplayTagQueryEdits.nest(
		root, GameplayTagQueryExpression.Operator.ANY
	)
	var both: GameplayTagQueryExpression = GameplayTagQueryEdits.nest(
		either, GameplayTagQueryExpression.Operator.ALL
	)
	GameplayTagQueryEdits.add_tag(both, A)
	GameplayTagQueryEdits.add_tag(both, B)
	GameplayTagQueryEdits.add_tag(either, C)

	var neither: GameplayTagQueryExpression = GameplayTagQueryEdits.nest(
		root, GameplayTagQueryExpression.Operator.NONE
	)
	GameplayTagQueryEdits.add_tag(neither, D)
	return query


##     [what the target holds, what it is called, whether the query matches]
func _built_query_cases() -> Array:
	return [
		[[A, B], "both of the pair", true],
		[[C], "the alternative on its own", true],
		[[A], "half of the pair, and nothing else", false],
		[[A, B, D], "both of the pair, and the tag that rules it out", false],
		[[C, D], "the alternative, and the tag that rules it out", false],
		[[], "nothing at all", false],
	]


func test_a_query_built_by_editing_means_what_the_nesting_says(
	case: Array = use_parameters(_built_query_cases())
) -> void:
	var held: Array = case[0]
	var described: String = case[1]
	var matches: bool = case[2]

	var tags: Array[StringName] = []
	tags.assign(held)
	assert_eq(_built().matches_tags(tags), matches, described)


## A query somebody has just started building matches everything.
##
## ALL over nothing, which is the neutral answer. ANY over nothing satisfies
## nobody, and an editor whose first click produced a query that refused every
## target would be an editor people work around.
func test_a_query_that_has_only_just_been_started_matches_everything() -> void:
	var query: GameplayTagQuery = GameplayTagQuery.new()
	var root: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(query)

	assert_eq(root.operator, GameplayTagQueryExpression.Operator.ALL, "ALL to begin with")
	assert_true(query.matches_tags([] as Array[StringName]), "so it imposes nothing yet")
	assert_same(root, GameplayTagQueryEdits.ensure_root(query), "and asking again is the same one")


## Changing an operator changes what an expression means and nothing under it.
func test_changing_an_operator_leaves_everything_under_it_alone() -> void:
	var query: GameplayTagQuery = GameplayTagQuery.new()
	var root: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(query)
	GameplayTagQueryEdits.add_tag(root, A)
	GameplayTagQueryEdits.add_tag(root, B)
	var both: Array[StringName] = [A, B]

	assert_true(query.matches_tags(both), "ALL of them, and it holds both")
	GameplayTagQueryEdits.set_operator(root, GameplayTagQueryExpression.Operator.NONE)

	assert_eq(root.tags.size(), 2, "the tags are still there")
	assert_false(query.matches_tags(both), "and the query now says the opposite")


## One tag twice is not twice as true.
func test_a_tag_already_on_an_expression_is_not_added_again() -> void:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()

	assert_true(GameplayTagQueryEdits.add_tag(expression, A), "added")
	assert_false(GameplayTagQueryEdits.add_tag(expression, A), "and not a second time")
	assert_false(GameplayTagQueryEdits.add_tag(expression, &""), "nor is nothing a tag")
	assert_eq(expression.tags, [A] as Array[StringName], "one condition, once")
#endregion


#region The rows the editor draws
## Every row, in the order the editor draws them, indented by its nesting.
##
## An expression before what is under it, its own tags before its nested
## expressions - so a row's indentation is the nesting the runtime evaluates
## rather than an order the screen invented.
func test_the_rows_are_the_nesting_the_runtime_evaluates() -> void:
	var query: GameplayTagQuery = _built()
	assert_eq(GameplayTagQueryEdits.depth_of(query.root), 3, "three levels of nesting")

	var rows: Array[GameplayTagQueryEdits.Row] = GameplayTagQueryEdits.rows_of(query)
	var drawn: Array[String] = []
	for row: GameplayTagQueryEdits.Row in rows:
		drawn.append("%d:%s" % [row.depth, row.shown()])

	assert_eq(
		drawn,
		[
			"0:ALL",
			"1:ANY",
			"2:Status.Poisoned",
			"2:ALL",
			"3:Status.Burning",
			"3:Status.Bleeding",
			"1:NONE",
			"2:Status.Immune",
		] as Array[String],
		"the whole tree, in reading order"
	)


## A tag row knows which expression it belongs to, which is how its picker and
## its delete button know what they are acting on.
func test_a_tag_row_carries_the_expression_it_belongs_to() -> void:
	var query: GameplayTagQuery = _built()
	var rows: Array[GameplayTagQueryEdits.Row] = GameplayTagQueryEdits.rows_of(query)

	var leaf: GameplayTagQueryEdits.Row = rows[4]
	assert_true(leaf.is_a_tag(), "the row is a tag")
	assert_eq(leaf.tag, A, "and it is this one")
	assert_true(leaf.expression.tags.has(A), "held by the expression the row names")
	assert_false(rows[0].is_a_tag(), "while the root is an expression")


## An empty query draws nothing, and a query with a root draws it.
func test_a_query_with_no_root_draws_nothing() -> void:
	assert_eq(
		GameplayTagQueryEdits.rows_of(GameplayTagQuery.new()).size(), 0,
		"nothing to draw, which is what an unrestricted query is"
	)
	assert_eq(GameplayTagQueryEdits.rows_of(null).size(), 0, "and nothing is not a query")


## A cycle is listed once and not descended into.
##
## A corrupted definition the runtime already refuses to evaluate. The author
## has to be able to see the row that is wrong and delete it, so the editor
## draws it - an editor that hung on the file it was asked to repair would be
## no help at all.
func test_a_cycle_is_drawn_once_rather_than_followed() -> void:
	var query: GameplayTagQuery = GameplayTagQuery.new()
	var root: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(query)
	var nested: GameplayTagQueryExpression = GameplayTagQueryEdits.nest(root)
	nested.expressions.append(root)

	var rows: Array[GameplayTagQueryEdits.Row] = GameplayTagQueryEdits.rows_of(query)

	assert_eq(rows.size(), 3, "the root, what is under it, and the way back - once")
	assert_same(rows[2].expression, root, "the row that closes the loop is the root again")
	assert_eq(
		GameplayTagQueryEdits.depth_of(root), 64,
		"and measuring its depth counts to the limit and stops, rather than running forever"
	)
#endregion


#region Taking things out
## Removing a nested expression takes everything under it with it.
func test_removing_an_expression_takes_what_is_under_it() -> void:
	var query: GameplayTagQuery = _built()
	var root: GameplayTagQueryExpression = query.root
	var either: GameplayTagQueryExpression = root.expressions[0]

	assert_true(GameplayTagQueryEdits.drop(root, either), "the ANY branch was removed")

	var drawn: Array[String] = []
	for row: GameplayTagQueryEdits.Row in GameplayTagQueryEdits.rows_of(query):
		drawn.append(row.shown())
	assert_eq(drawn, ["ALL", "NONE", "Status.Immune"] as Array[String], "and its three rows with it")


## Removal by identity, because the tree is rebuilt on every edit.
##
## An index read off a row drawn before the last edit points at whichever
## sibling has since moved into it - which is a different branch deleted than
## the one somebody clicked.
func test_removal_names_the_expression_rather_than_a_position() -> void:
	var root: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	var first: GameplayTagQueryExpression = GameplayTagQueryEdits.nest(root)
	var second: GameplayTagQueryExpression = GameplayTagQueryEdits.nest(root)

	assert_true(GameplayTagQueryEdits.drop(root, first), "the first one went")
	assert_same(root.expressions[0], second, "and the second moved into its place")
	assert_false(GameplayTagQueryEdits.drop(root, first), "removing it again does nothing")
	assert_false(
		GameplayTagQueryEdits.unnest(root, 7), "and neither does a position that names nothing"
	)


func test_removing_a_tag_removes_that_tag() -> void:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	GameplayTagQueryEdits.add_tag(expression, A)
	GameplayTagQueryEdits.add_tag(expression, B)

	assert_true(GameplayTagQueryEdits.remove_tag(expression, A), "it was there")
	assert_eq(expression.tags, [B] as Array[StringName], "and the other one stayed")
	assert_false(GameplayTagQueryEdits.remove_tag(expression, A), "removing it again does nothing")
#endregion


#region Where the editor is offered
## The plugin offers the query editor for a query and for nothing else.
##
## By the property's type, so a query on a target filter gets the editor without
## anybody having to add its name to a list.
##
##     [what it is called, the type, the hint, whether the editor is offered]
func _handled_cases() -> Array:
	return [
		["a tag query", TYPE_OBJECT, "GameplayTagQuery", true],
		["one of its expressions", TYPE_OBJECT, "GameplayTagQueryExpression", false],
		["some other Resource", TYPE_OBJECT, "Curve", false],
		["a list of tags", TYPE_ARRAY, "", false],
	]


func test_the_editor_is_offered_for_a_query_and_nothing_else(
	case: Array = use_parameters(_handled_cases())
) -> void:
	var described: String = case[0]
	var type: Variant.Type = case[1]
	var hint: String = case[2]
	var offered: bool = case[3]

	assert_eq(InspectorPlugin.is_a_tag_query(type, hint), offered, described)
#endregion


#region What a node says it is
## A node with no ability system still has tags, if it says so.
func test_a_node_with_no_ability_system_answers_for_itself() -> void:
	var door: ADoor = ADoor.new()
	autofree(door)
	door.says = [A] as Array[StringName]

	assert_true(GameplayTagOwner.speaks_for_itself(door), "it has an opinion")
	assert_eq(GameplayTagOwner.tags_of(door), [A] as Array[StringName], "and this is it")
	assert_true(GameplayTagOwner.is_tagged(door), "so it is tagged")


## Something that says nothing has no tags, which is a perfectly good answer.
func test_something_that_says_nothing_has_no_tags() -> void:
	var wall: AWall = AWall.new()
	autofree(wall)

	assert_false(GameplayTagOwner.speaks_for_itself(wall), "no opinion")
	assert_eq(GameplayTagOwner.tags_of(wall).size(), 0, "and no tags")
	assert_eq(GameplayTagOwner.tags_of(null).size(), 0, "nor has nothing")


## A door that is currently unlocked still has an opinion.
##
## Asked apart from being tagged because they are different questions, and a
## filter that conflated them would stop seeing the door the moment it opened.
func test_a_node_that_answers_with_nothing_still_speaks_for_itself() -> void:
	var door: ADoor = ADoor.new()
	autofree(door)

	assert_true(GameplayTagOwner.speaks_for_itself(door), "it answers")
	assert_false(GameplayTagOwner.is_tagged(door), "with nothing, just now")


## Both sources count, and neither is dropped for the other.
##
## A node that has an ability system AND answers the method is saying both
## things about itself; keeping only one would be the addon deciding which of
## somebody's two answers was the real one.
func test_both_sources_of_tags_count() -> void:
	var door: ADoor = ADoor.new()
	autofree(door)
	door.says = [A] as Array[StringName]
	var asc: AbilitySystemComponent = AbilitySystemComponent.new()
	door.add_child(asc)
	asc.tags.add(B)

	var found: Array[StringName] = GameplayTagOwner.tags_of(door)

	assert_true(found.has(A), "what the node said")
	assert_true(found.has(B), "and what its ability system holds")


## Whatever a node hands back is filtered to names.
##
## Somebody else's method, and its return type is theirs to get wrong. A list
## with a number in it is a mistake worth ignoring rather than one worth
## crashing a sweep across a room for.
func test_a_tag_said_twice_is_one_tag() -> void:
	var door: ADoor = ADoor.new()
	autofree(door)
	door.says = [A, A] as Array[StringName]

	assert_eq(GameplayTagOwner.tags_of(door), [A] as Array[StringName], "once")


## A query can be asked about a node, not only about a runtime.
func test_a_query_can_be_asked_about_anything_that_has_tags() -> void:
	var query: GameplayTagQuery = GameplayTagQuery.new()
	var root: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(query)
	GameplayTagQueryEdits.add_tag(root, A)

	var door: ADoor = ADoor.new()
	autofree(door)
	var wall: AWall = AWall.new()
	autofree(wall)

	assert_false(query.matches_node(door), "the door does not hold it yet")
	door.says = [A] as Array[StringName]
	assert_true(query.matches_node(door), "and now it does")
	assert_false(query.matches_node(wall), "while the wall never will")


## A target filter accepts a node that has no ability system and says so.
##
## The filter used to reach tags only through an ability system, so a door was
## not a target however locked it was - and a required-tag filter over a room
## quietly skipped every piece of scenery in it.
func test_a_target_filter_sees_a_node_that_answers_for_itself() -> void:
	var door: ADoor = ADoor.new()
	autofree(door)
	door.says = [A] as Array[StringName]
	var wall: AWall = AWall.new()
	autofree(wall)

	var filter: GameplayTargetFilter = GameplayTargetFilter.new()
	filter.required_tags = [A] as Array[StringName]

	assert_true(filter.accepts(null, door), "the door carries what was asked for")
	assert_false(filter.accepts(null, wall), "the wall carries nothing and is not a target")

	filter.required_tags = [] as Array[StringName]
	filter.blocked_tags = [A] as Array[StringName]
	assert_false(filter.accepts(null, door), "and a blocked tag is seen the same way")
#endregion
