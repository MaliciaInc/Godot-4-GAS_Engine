## Who an ability belongs to, and who it happens to.
##
## Usually the same node, and the reason this exists is the case where they are
## not. A player's abilities belong to the player and happen to whatever they
## are currently driving; a possessed body, a mount, a vehicle. The component
## has to stay where the grants are while what the effects and cues act on
## changes underneath it.
##
## The controller is neither: it is whoever is issuing the orders, kept so an
## ability can ask without walking the tree and guessing.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilityActorInfo extends RefCounted

var owner: Node = null
var avatar: Node = null
var controller: Node = null

func initialize(in_owner: Node, in_avatar: Node = null, in_controller: Node = null) -> void:
	owner = in_owner
	avatar = in_avatar if in_avatar != null else in_owner
	controller = in_controller

func clear() -> void:
	owner = null
	avatar = null
	controller = null
