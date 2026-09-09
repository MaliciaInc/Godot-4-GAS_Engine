## A hit that lands the moment it is pressed.
##
## The smallest complete ability there is: it commits - paying nothing, starting
## a cooldown - applies one instant effect to whoever it was aimed at, and plays
## a burst. Everything else in this sample is this with something added.
##
## Aimed rather than assumed: the target arrives as target data, which is what
## a provider, a task, or a game's own code hands in. An ability that reached
## into the world to find somebody would be an ability the game cannot aim.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name SampleBasicAttack extends GameplayAbility

const TAG: StringName = &"Ability.Sample.Strike"
const COOLDOWN_SECONDS: float = 1.5

## Who it hit, in the order it hit them. Read by the sample's probe, and by
## anybody wondering whether the aim landed.
var struck: Array[Node] = []


static func build() -> SampleBasicAttack:
	var ability: SampleBasicAttack = SampleBasicAttack.new()
	ability.name = "SampleBasicAttack"
	ability.ability_name = "Strike"
	ability.ability_tags = [TAG]
	ability.cooldown_effect = SampleEffects.strike_cooldown(COOLDOWN_SECONDS)
	# It ends when the activation function returns, because there is nothing to
	# wait for: the hit has already landed by then.
	ability.auto_end_on_activate_return = true
	return ability


## Hit whatever this activation was aimed at.
##
## False when there was nothing to hit. A refusal rather than a hit on nobody,
## so a caller that forgot to aim finds out rather than watching an animation
## play against the air.
func _activate_ability() -> bool:
	struck.clear()
	if not commit_ability().is_ok():
		return false

	var data: GameplayAbilityTargetData = get_activation_target_data()
	if data == null or not data.has_targets():
		return false

	# One spec per target rather than one shared across them, which is what
	# `apply_effect_to_targets` is for: sharing let the first target's
	# evaluation change what the second one received.
	apply_effect_to_targets(SampleEffects.strike(), data)
	struck.assign(data.get_target_nodes())

	execute_cue(SampleCues.STRIKE_IMPACT)
	return not struck.is_empty()
