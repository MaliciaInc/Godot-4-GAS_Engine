## A provider that aims at whatever it is told to.
##
## The lifecycle of choosing a target - begin, preview, confirm or cancel - is
## the same whether a physics world answered the aim or a test did, and it is
## the part that breaks. This makes it drivable without a world: set what it is
## aimed at, ask it to preview, and assert what came back.
##
## Shared by the provider's own suite and by the F5.4 gate walk, because two
## copies of it are two places for one of them to start aiming differently.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name FixedTargetProvider extends GameplayTargetProvider

var aimed_at: Array[Node] = []


func _aim() -> GameplayAbilityTargetData:
	var found: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	for node: Node in aimed_at:
		found.append_node(node)
	return found
