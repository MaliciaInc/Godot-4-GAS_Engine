## A second game's calls, one of which is named the same as another game's.
##
## Exists so the catalog can be asked the question the engine itself asks: two
## scripts declaring one method name. `execute_cue` is on both GameplayAbility
## and AbilitySystemComponent, so a catalog that could hold only one of them
## could not draw the other - and this is the same shape, from outside.
##
## @meta_license: MIT
extends RefCounted

var spent: float = 0.0


## Named the same as the one on game_composer_nodes.gd, and taking something
## else. Two calls, one name, and only the receiver tells them apart.
func spend_stamina(cost: int) -> void:
	spent += float(cost)
