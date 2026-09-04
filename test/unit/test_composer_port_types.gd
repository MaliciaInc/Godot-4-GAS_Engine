## The integers GraphEdit is told about, and what they must never do.
##
## Two properties carry everything. The numbers have to be the same every time
## the same ability is numbered, because a pin that changes number between the
## start of a drag and its end is a pin the drop is refused on for no reason
## anybody can see. And the pairs registered have to be exactly what
## `ComposerTypes` allows, because a widget that is more permissive than the
## rules lets a wire land that the controller then refuses - which reads as the
## tool changing its mind.
##
## The colours are checked for consistency, never for exact values. A test that
## pinned RGB would fail on every deliberate adjustment to the palette and pass
## on every real mistake.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"

## A body using several value types at once, so the numbering has something to
## order. The names are deliberately not in alphabetical order in the file: the
## whole point of sorting is that the file's order does not decide the numbers.
const MIXED: Array = [
	"var strength: float = 2.0",
	"var caster: AbilitySystemComponent = owner_asc",
	"var count: int = 1",
	"apply_gameplay_effect(burning, caster, strength)",
	"return true",
]

var _types: ComposerPortTypes = null
var _edit: GraphEdit = null


func before_each() -> void:
	_types = ComposerPortTypes.new()


func after_each() -> void:
	if _edit != null:
		_edit.free()
		_edit = null


#region Getting there
func _read(statements: Array) -> ComposerGraph:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	return ComposerReader.read(HEAD + body, PATH)


## Every value pin in the graph, as "type name -> number".
func _numbering(graph: ComposerGraph) -> Dictionary[StringName, int]:
	var found: Dictionary[StringName, int] = {}
	for node: ComposerNode in graph.visible_nodes():
		for pin: ComposerNode.Port in node.ports:
			if pin.is_execution():
				continue
			found[pin.type_name] = _types.ui_type(pin.type_name, pin.kind)
	return found


## A GraphEdit with this graph's pairs registered on it.
func _registered(graph: ComposerGraph) -> GraphEdit:
	_edit = GraphEdit.new()
	_types.register_into(_edit, graph)
	return _edit


## The number the last rebuild gave that value type.
func _number_of(type_name: StringName) -> int:
	return _types.ui_type(type_name, ComposerNode.PortKind.DATA)
#endregion


#region The numbers
## Execution is the same number everywhere, whatever the ability holds.
##
## Pinned rather than worked out, so a canvas renumbered mid-drag cannot move
## the run of control out from under the wire being dragged.
func test_execution_is_always_the_same_number() -> void:
	var bare: ComposerGraph = _read(["return true"])
	var mixed: ComposerGraph = _read(MIXED)

	_types.rebuild(bare)
	var alone: int = _types.ui_type(&"", ComposerNode.PortKind.EXECUTION)
	_types.rebuild(mixed)
	var crowded: int = _types.ui_type(&"float", ComposerNode.PortKind.EXECUTION)

	assert_eq(alone, ComposerPortTypes.EXECUTION_TYPE, "an ability with nothing in it")
	assert_eq(crowded, ComposerPortTypes.EXECUTION_TYPE, "and one with several types")


## The same ability numbers the same way every time it is numbered.
func test_numbering_the_same_graph_twice_gives_the_same_numbers() -> void:
	var graph: ComposerGraph = _read(MIXED)

	_types.rebuild(graph)
	var first: Dictionary[StringName, int] = _numbering(graph)
	_types.rebuild(graph)
	var again: Dictionary[StringName, int] = _numbering(graph)

	assert_gt(first.size(), 1, "there is more than one type to get wrong")
	assert_eq(first, again, "and both passes agree")


## Two abilities that use the same types number them the same, however their
## statements happen to be ordered.
##
## This is the property that matters, and the one a single-graph test cannot
## see: numbering by the order pins were read would pass "twice over the same
## graph" and still hand two arrangements of the same ability different numbers.
func test_the_order_statements_are_written_in_does_not_change_the_numbers() -> void:
	var written: ComposerGraph = _read(MIXED)
	var reordered: ComposerGraph = _read([
		"var count: int = 1",
		"var strength: float = 2.0",
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, caster, strength)",
		"return true",
	])

	_types.rebuild(written)
	var one: Dictionary[StringName, int] = _numbering(written)
	_types.rebuild(reordered)
	var other: Dictionary[StringName, int] = _numbering(reordered)

	assert_eq(one, other, "the same types get the same numbers")


## Value numbers start clear of the execution one, so a slip lands on nothing.
func test_value_numbers_are_nowhere_near_the_execution_one() -> void:
	var graph: ComposerGraph = _read(MIXED)
	_types.rebuild(graph)

	for type_name: StringName in _numbering(graph):
		assert_gte(
			_types.ui_type(type_name, ComposerNode.PortKind.DATA),
			ComposerPortTypes.DATA_BASE,
			"%s is a value number" % type_name
		)
#endregion


#region What GraphEdit is allowed to accept
## A type accepts itself, and the widget is told so.
func test_a_value_may_be_dropped_on_its_own_type() -> void:
	var graph: ComposerGraph = _read(MIXED)
	var edit: GraphEdit = _registered(graph)
	var number: int = _number_of(&"float")

	assert_true(edit.is_valid_connection_type(number, number), "float fits float")


## A run of control joins a run of control, and nothing else.
func test_execution_joins_execution_and_never_a_value() -> void:
	var graph: ComposerGraph = _read(MIXED)
	var edit: GraphEdit = _registered(graph)
	var exec: int = ComposerPortTypes.EXECUTION_TYPE
	var value: int = _number_of(&"float")

	assert_true(edit.is_valid_connection_type(exec, exec), "a run leads to a run")
	assert_false(edit.is_valid_connection_type(value, exec), "a value is not a run")
	assert_false(edit.is_valid_connection_type(exec, value), "and a run is not a value")


## What the widget accepts is exactly what `ComposerTypes` accepts.
##
## Checked pair by pair over every type the ability uses rather than on a chosen
## example, because the failure that matters is one pair being more permissive
## than the rules - and that is precisely the pair nobody thought to name.
func test_every_registered_pair_is_one_the_rules_allow() -> void:
	var graph: ComposerGraph = _read(MIXED)
	var edit: GraphEdit = _registered(graph)
	var numbering: Dictionary[StringName, int] = _numbering(graph)

	var compared: int = 0
	for source: StringName in numbering:
		for target: StringName in numbering:
			var registered: bool = edit.is_valid_connection_type(
				numbering[source], numbering[target]
			)
			assert_eq(
				registered,
				ComposerTypes.accepts(target, source),
				"%s into %s" % [source, target]
			)
			compared += 1

	assert_gt(compared, 4, "several pairs were actually compared")


## An int may be dropped on a float and a float may not be dropped on an int.
##
## Named on its own because it is the one widening GDScript does, so it is the
## one pair where "the rules" and "the same type" disagree - and getting it
## backwards would quietly lose somebody's fraction.
func test_the_one_widening_goes_one_way_only() -> void:
	var graph: ComposerGraph = _read(MIXED)
	var edit: GraphEdit = _registered(graph)
	var whole: int = _number_of(&"int")
	var fractional: int = _number_of(&"float")

	assert_true(edit.is_valid_connection_type(whole, fractional), "an int fits a float")
	assert_false(
		edit.is_valid_connection_type(fractional, whole), "a float does not fit an int"
	)


## A class fits where its ancestor is wanted, and the widget follows.
func test_a_class_reaches_the_ancestor_the_rules_say_it_does() -> void:
	var graph: ComposerGraph = _read([
		"var caster: AbilitySystemComponent = owner_asc",
		"var anything: Node = owner_asc",
		"apply_gameplay_effect(burning, caster, 1.0)",
		"return true",
	])
	var edit: GraphEdit = _registered(graph)
	var component: int = _number_of(&"AbilitySystemComponent")
	var node: int = _number_of(&"Node")

	assert_true(
		ComposerTypes.inherits(&"AbilitySystemComponent", &"Node"),
		"the rules say a component is a node"
	)
	assert_true(edit.is_valid_connection_type(component, node), "so the widget does")


## Numbering a second ability forgets the first one's pairs.
##
## Left behind, they would let somebody drop a wire between two types the open
## ability never mentions - and the numbers are reused, so the leftovers do not
## even mean what they used to.
func test_registering_a_second_ability_drops_the_first_ones_pairs() -> void:
	var mixed: ComposerGraph = _read(MIXED)
	var edit: GraphEdit = _registered(mixed)
	var whole: int = _number_of(&"int")
	var fractional: int = _number_of(&"float")
	assert_true(edit.is_valid_connection_type(whole, fractional), "registered at first")

	_types.register_into(edit, _read(["return true"]))

	assert_false(
		edit.is_valid_connection_type(whole, fractional),
		"an ability with no values registers no value pairs"
	)
	assert_true(
		edit.is_valid_connection_type(
			ComposerPortTypes.EXECUTION_TYPE, ComposerPortTypes.EXECUTION_TYPE
		),
		"and a run of control still leads to one"
	)
#endregion


#region The colours
## A pin's colour depends on what it carries and on nothing else.
func test_the_same_family_is_always_the_same_colour() -> void:
	assert_eq(
		_types.color_for(&"String", ComposerNode.PortKind.DATA),
		_types.color_for(&"StringName", ComposerNode.PortKind.DATA),
		"text is text"
	)
	assert_eq(
		_types.color_for(&"Vector2", ComposerNode.PortKind.DATA),
		_types.color_for(&"Vector3", ComposerNode.PortKind.DATA),
		"and a vector is a vector"
	)


## The families a person has to tell apart are actually told apart.
##
## Every distinct colour in the palette, compared against every other. A palette
## that quietly assigned two families the same colour would pass every test that
## only checked the ones it thought to name.
const DISTINCT: Array = [&"bool", &"int", &"float", &"String", &"NodePath", &"Vector2"]


func test_families_meant_to_differ_do_differ() -> void:
	for one: StringName in DISTINCT:
		for other: StringName in DISTINCT:
			if one == other:
				continue
			assert_ne(
				_types.color_for(one, ComposerNode.PortKind.DATA),
				_types.color_for(other, ComposerNode.PortKind.DATA),
				"%s is not %s" % [one, other]
			)


## A run of control never looks like a value, and an unknown class never looks
## like nothing.
func test_execution_and_the_unknown_are_told_apart() -> void:
	var run: Color = _types.color_for(&"", ComposerNode.PortKind.EXECUTION)
	var whatever: Color = _types.color_for(&"SomeGameClass", ComposerNode.PortKind.DATA)
	var untyped: Color = _types.color_for(&"Variant", ComposerNode.PortKind.DATA)

	assert_ne(run, whatever, "a run of control is not a thing being carried")
	assert_ne(whatever, untyped, "and a class is not an unknown")
#endregion
