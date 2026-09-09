## Everything a grant can be told, for the grants that need more than three
## things said about them.
##
## An object rather than more parameters on give_ability(). The three-argument
## call is what most grants are and it stays exactly what it was; a grant that
## also names an input action is saying something specific enough to be worth
## its own shape, and a fifth positional argument is one nobody reads at the
## call site.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilityGrantOptions extends RefCounted

var level: float = 1.0

## The numeric slot, for a game that routes input by slot.
var input_id: int = -1

## The InputMap action, for a game that routes by name. Both may be set: they
## are two ways of reaching one grant, not two grants.
var input_action: StringName = &""

var source: GameplayAbilitySource = null
