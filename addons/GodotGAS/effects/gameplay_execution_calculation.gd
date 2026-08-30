## Base class for custom mathematical calculations inside the GodotGAS framework.
##
## Override the execute() function to perform complex combat math 
## (e.g., Damage = Caster.Attack - Target.Defense).
##
## @meta_addon: GodotGAS Version 1 (See plugin version for exact version)
## @meta_author: YulRun (https://YulRun.Dev)
## @meta_license: MIT

@abstract
@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
class_name GameplayExecutionCalculation extends Resource


#region Execution
## Compute flat deltas against the target's underlying base state.
##
## Section 3.7: an execution calculation is an instant mutation of the durable
## value, never a temporary contribution. A Fireball may read Attack, Defense,
## tags and level and return a change to Health; a +20% Attack buff is a
## standard modifier instead, so that it lives and dies with its effect.
##
## The returned Dictionary is typed and is an extension boundary: user scripts
## outside this addon produce it, and GameplayEffectEvaluator converts it into
## staged AttributeBaseMutations before it reaches anything else. It is never
## carried through the runtime as a payload.
##
## An attribute this returns a delta for must NOT also be written by a standard
## modifier of the same effect. That combination has no defined order and the
## evaluator refuses the whole application with AMBIGUOUS_ATTRIBUTE_WRITE.
func execute(
	_spec: GameplayEffectSpec, _target_asc: AbilitySystemComponent
) -> Dictionary[StringName, float]:
	push_error(
		"GodotGAS: execute() called on the base GameplayExecutionCalculation. "
		+ "Override it in your specific child script."
	)
	return {}
#endregion
