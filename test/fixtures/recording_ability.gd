## An ability that records what it received instead of doing anything.
##
## A dedicated fixture rather than an inline test class, because a grant now
## always goes through packing a Node into a scene: an anonymous inline class
## has no script resource of its own to pack reliably, and this one does.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name RecordingAbility extends GameplayAbility

var activations: int = 0
var last_context: GameplayEffectContext = null


func _activate_ability() -> bool:
	activations += 1
	last_context = current_context
	return true
