## Finding the ability system a hit belongs to.
##
## A physics query answers with a collider, and a collider is almost never the
## thing that owns attributes. The walk from one to the other is short but has to
## be exactly right in both directions: far enough outward to reach the actor,
## and never inward far enough to reach somebody else's.
##
## The name is the part most likely to rot, so it is tested as what it is - a
## shortcut. A renamed component still resolves; a decoy wearing the name does
## not.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

## Borrowed rather than respelled: the locator owns what this name is.
const CANONICAL: StringName = AbilitySystemLocator.ASC_CHILD_NAME


#region Scenes
func _node(node_name: String) -> Node:
	var node: Node = Node.new()
	node.name = node_name
	return node


func _asc(node_name: String) -> AbilitySystemComponent:
	var component: AbilitySystemComponent = AbilitySystemComponent.new()
	component.name = node_name
	return component


## An actor carrying a component under `component_name`. Returns the component;
## its parent is the actor.
func _component_on_an_actor(component_name: String) -> AbilitySystemComponent:
	var actor: Node = _node("Actor")
	var component: AbilitySystemComponent = _asc(component_name)
	actor.add_child(component)
	add_child_autofree(actor)
	return component


## A collider buried `depth` links below the actor, the way a rig buries one.
func _collider_under(actor: Node, depth: int) -> Node:
	var parent: Node = actor
	for level: int in range(depth):
		var link: Node = _node("Link" + str(level))
		parent.add_child(link)
		parent = link
	var collider: Node = _node("Hitbox")
	parent.add_child(collider)
	return collider
#endregion


#region Finding it
func test_a_node_that_is_the_component_answers_itself() -> void:
	var component: AbilitySystemComponent = _asc("Anything")
	add_child_autofree(component)
	assert_eq(AbilitySystemLocator.find_for_node(component), component, "it is its own answer")


func test_a_child_under_the_conventional_name_is_found() -> void:
	var component: AbilitySystemComponent = _component_on_an_actor(String(CANONICAL))
	assert_eq(
		AbilitySystemLocator.find_for_node(component.get_parent()), component, "the usual case"
	)


## The name is an optimisation. A renamed component is still a component.
func test_a_renamed_child_still_resolves_by_type() -> void:
	var component: AbilitySystemComponent = _component_on_an_actor("Stats")
	assert_eq(
		AbilitySystemLocator.find_for_node(component.get_parent()),
		component,
		"type decides, not spelling"
	)


## And a node wearing the name without the type is a naming accident.
func test_a_decoy_using_the_name_is_not_accepted() -> void:
	var component: AbilitySystemComponent = _component_on_an_actor("Stats")
	var actor: Node = component.get_parent()
	actor.add_child(_node(String(CANONICAL)))

	assert_eq(
		AbilitySystemLocator.find_for_node(actor), component, "the real one, not the one named so"
	)


func test_a_collider_finds_the_component_beside_it() -> void:
	var component: AbilitySystemComponent = _component_on_an_actor(String(CANONICAL))
	var collider: Node = _collider_under(component.get_parent(), 0)
	assert_eq(AbilitySystemLocator.find_for_node(collider), component, "a sibling is reachable")


func test_the_search_climbs_past_more_than_one_ancestor() -> void:
	var component: AbilitySystemComponent = _component_on_an_actor(String(CANONICAL))
	var collider: Node = _collider_under(component.get_parent(), 3)
	assert_eq(AbilitySystemLocator.find_for_node(collider), component, "three levels up is fine")


func test_nothing_is_found_when_there_is_nothing_to_find() -> void:
	var lonely: Node = _node("Scenery")
	add_child_autofree(lonely)
	assert_null(AbilitySystemLocator.find_for_node(lonely), "no component anywhere above it")
	assert_null(AbilitySystemLocator.find_for_node(null), "and null is answered, not crashed on")
#endregion


#region Not finding somebody else's
## A component buried inside a descendant belongs to that descendant.
##
## Hitting a character's sword must not charge the sword's own ability system,
## and a vehicle must not answer for the passenger standing inside it. The search
## goes outward and looks one level down; it never descends.
func test_a_component_inside_a_descendant_is_not_captured() -> void:
	var vehicle: Node = _node("Vehicle")
	var passenger: Node = _node("Passenger")
	passenger.add_child(_asc(String(CANONICAL)))
	vehicle.add_child(passenger)
	add_child_autofree(vehicle)

	assert_null(
		AbilitySystemLocator.find_for_node(vehicle),
		"the vehicle has none of its own, and the passenger's is not its to take"
	)


func test_the_ability_facade_and_the_locator_are_the_same_search() -> void:
	var component: AbilitySystemComponent = _component_on_an_actor("Stats")
	var collider: Node = _collider_under(component.get_parent(), 1)

	# One algorithm behind two doors, rather than two that drift apart.
	assert_eq(
		GameplayAbility.find_asc_on(collider),
		AbilitySystemLocator.find_for_node(collider),
		"the public helper answers with the locator"
	)
#endregion
