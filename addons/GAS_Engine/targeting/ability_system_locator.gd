## Find the ability system a node belongs to.
##
## A physics query returns a collider, and a collider is rarely the thing that
## owns attributes: it is a shape under a body under an actor. Something has to
## walk from what was hit to whoever it belongs to, and doing that at each call
## site produced several slightly different walks.
##
## The search goes outward only - the node, then its parents - and looks one
## level down at each step. It never descends recursively, because a component
## buried inside a descendant belongs to that descendant. Hitting a character's
## sword must not apply the effect to the sword's own ability system, and it must
## not reach a passenger standing inside a vehicle either.
##
## The conventional child name is consulted first as a shortcut and is never the
## contract: a node is an ability system because of its type, so a renamed one
## still resolves and a decoy with the right name does not.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name AbilitySystemLocator extends RefCounted

## The name the component is conventionally given. An optimisation, not a rule.
const ASC_CHILD_NAME: StringName = &"AbilitySystemComponent"


static func find_for_node(node: Node) -> AbilitySystemComponent:
	var candidate: Node = node
	while candidate != null:
		var itself: AbilitySystemComponent = candidate as AbilitySystemComponent
		if itself != null:
			return itself

		# The shortcut: a direct child under the conventional name, accepted only
		# when it really is one. A node called AbilitySystemComponent that is not
		# an ability system is a naming accident, not an answer.
		var named: Node = candidate.get_node_or_null(NodePath(String(ASC_CHILD_NAME)))
		var named_asc: AbilitySystemComponent = named as AbilitySystemComponent
		if named_asc != null:
			return named_asc

		for child: Node in candidate.get_children():
			if child == named:
				continue
			var child_asc: AbilitySystemComponent = child as AbilitySystemComponent
			if child_asc != null:
				return child_asc

		candidate = candidate.get_parent()
	return null
