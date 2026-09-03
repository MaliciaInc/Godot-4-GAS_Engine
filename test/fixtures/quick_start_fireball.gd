## The ability the README's quick start prints, kept runnable.
##
## Named `Fireball` there and `QuickStartFireball` here for the reason
## [QuickStartAttributes] carries: this repository already spends `Fireball` on
## a Composer test double.
##
## The effect is built here, in code, from the ability's own exported number.
## There is deliberately no authored-resource twin: two ways to say what an
## ability does is two places to look when it does the wrong thing, and the
## hand-written one is the one nothing can check.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name QuickStartFireball extends GameplayAbility

## What this takes off a target's health.
@export var damage: float = 30.0

## Who it is aimed at. A real game decides targets outside the ability; a group
## keeps the printed example to one file.
@export var enemies_group: StringName = &"enemies"


func _activate_ability() -> bool:
	# Paid first. Nothing has happened yet, so a refusal costs nothing to undo.
	if not commit_ability().is_ok():
		return false

	var struck: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	for enemy: Node in get_tree().get_nodes_in_group(enemies_group):
		var theirs: AbilitySystemComponent = AbilitySystemLocator.find_for_node(enemy)
		if theirs != null:
			struck.append_node(theirs)

	apply_effect_to_targets(_payload(), struck)
	end_ability()
	return true


## A modifier is a contribution, not a write: it does not set health, it
## registers what this blow contributes and lets the target's own set compose it.
func _payload() -> GameplayEffect:
	var how_much: GameplayScalableFloat = GameplayScalableFloat.new()
	how_much.value = -damage

	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = how_much

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = QuickStartAttributes.HEALTH
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude

	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.modifiers = [modifier] as Array[GameplayEffectModifier]
	return effect
