## A receipt for one attribute set this component adopted.
##
## The instance actually adopted, not the one that was handed in. A component
## that isolates its attributes duplicates what it is given - which is the whole
## point, so two characters built from one authored set do not share a health
## pool - and a handle holding the original would name something the component
## has never seen.
##
## It also names the component, so a receipt from one entity cannot retire a set
## on another. That is not a hypothetical: a loadout is a Resource, and the same
## Resource is granted to every character in the game.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name RegisteredAttributeSetHandle extends RefCounted

## The set the component is actually holding.
var adopted: AttributeSet = null

## Which component adopted it.
var owner_asc: AbilitySystemComponent = null


static func of(adopted: AttributeSet, owner: AbilitySystemComponent) -> RegisteredAttributeSetHandle:
	var handle: RegisteredAttributeSetHandle = RegisteredAttributeSetHandle.new()
	handle.adopted = adopted
	handle.owner_asc = owner
	return handle


func is_valid() -> bool:
	return adopted != null and owner_asc != null and is_instance_valid(owner_asc)
