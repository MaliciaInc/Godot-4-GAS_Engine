## Aim at whoever is casting.
##
## The simplest step there is, and the one a self-buff preset is made of. Also
## the honest start for "everybody around me except me": select the source, then
## select an area, then filter the source back out - three steps that say what
## they mean, rather than one flag on an area step.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name TargetingSelectSource extends GameplayTargetingTask


func execute(
	input: GameplayAbilityTargetData, source_asc: AbilitySystemComponent
) -> GameplayAbilityTargetData:
	if source_asc == null:
		return input
	var body: Node = source_asc.get_effect_target()
	if body == null or not is_instance_valid(body):
		return input
	input.append_node(body)
	return input
