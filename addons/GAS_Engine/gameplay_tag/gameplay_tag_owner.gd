## What tags a node has, asked of the node itself.
##
## An ability system is one way of having tags and not the only one. A door that
## is `Locked`, a region that is `Indoors`, a piece of cover that is `Waist
## High` - none of those want an AbilitySystemComponent, and a targeting filter
## that could only see tags through one would have to treat all of them as
## untagged.
##
## Duck-typed rather than an interface class: a game's door already extends
## whatever it extends, and a Node it had to re-parent to be tagged is a tax on
## the game for the addon's convenience.
##
## The two sources are asked in a fixed order and both count. A node that has an
## ability system AND answers the method is saying both things about itself, and
## dropping either would be the addon deciding which of somebody's two answers
## was the real one.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTagOwner extends RefCounted

## The method a node implements to say what it is.
const METHOD: StringName = &"get_owned_gameplay_tags"


## Every tag this node has, from its ability system and from its own answer.
##
## Empty for a node that is neither, which is most of a scene - and is a
## perfectly good answer: a wall has no tags, and asking is how that is found
## out rather than something to be avoided.
static func tags_of(node: Node) -> Array[StringName]:
	var found: Array[StringName] = []
	if node == null or not is_instance_valid(node):
		return found

	var asc: AbilitySystemComponent = AbilitySystemLocator.find_for_node(node)
	if asc != null:
		found.append_array(asc.tags.active_tags())

	if not node.has_method(METHOD):
		return found
	# Whatever the node hands back, filtered to names: this is somebody else's
	# method and its return type is theirs to get wrong. A list with a number in
	# it is a mistake worth ignoring rather than one worth crashing a sweep for.
	for said: Variant in node.call(METHOD):
		if said is StringName or said is String:
			var tag: StringName = StringName(str(said))
			if not found.has(tag):
				found.append(tag)
	return found


## Whether this node says anything about itself at all.
static func is_tagged(node: Node) -> bool:
	return not tags_of(node).is_empty()


## Whether a node answers the method, whatever it answers with.
##
## Asked apart from `is_tagged` because they are different questions: a door
## that is currently unlocked answers the method with nothing, and is still a
## door that has an opinion.
static func speaks_for_itself(node: Node) -> bool:
	return node != null and is_instance_valid(node) and node.has_method(METHOD)
