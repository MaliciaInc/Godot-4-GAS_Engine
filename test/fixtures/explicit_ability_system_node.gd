## A node that says where its ability system is, rather than being under it.
##
## The pattern the locator's duck-typing exists for: a Pawn whose component
## lives on its PlayerState, an equipment node whose component is its wearer's.
## Nothing here inherits from anything in the addon - declaring the method is
## the whole contract, which is the point.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name ExplicitAbilitySystemNode extends Node

## The component this node answers with. Set by whoever builds it.
var declared: AbilitySystemComponent = null


func get_ability_system_component() -> AbilitySystemComponent:
	return declared
