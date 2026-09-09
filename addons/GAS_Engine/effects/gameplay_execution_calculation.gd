## Base class for custom mathematical calculations inside the GAS_Engine framework.
##
## Override the execute() function to perform complex combat math 
## (e.g., Damage = Caster.Attack - Target.Defense).
##
## @meta_addon: GAS_Engine Version 1 (See plugin version for exact version)
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@abstract
@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
class_name GameplayExecutionCalculation extends Resource


#region Execution
## Compute flat deltas against the target's underlying base state.
##
## An execution calculation is an instant mutation of the durable
## value, never a temporary contribution. A Fireball may read Attack, Defense,
## tags and level and return a change to Health; a +20% Attack buff is a
## standard modifier instead, so that it lives and dies with its effect.
##
## The returned Dictionary is typed and is an extension boundary: user scripts
## outside this addon produce it, and GameplayEffectEvaluator converts it into
## staged AttributeBaseMutations before it reaches anything else. It is never
## carried through the runtime as a payload.
##
## This has no gameplay side effects of its own: it reads state through
## `spec` and `_target_asc` and returns deltas, and must not grant a tag,
## apply or remove an effect, or write an attribute directly. The
## evaluator runs this while an application may still be refused - a
## divide-by-zero elsewhere in the same effect, say - and only its
## returned deltas are staged for that refusal to undo. A mutation made
## here happens whether or not the application it was part of ever
## commits.
##
## An attribute this returns a delta for may also be written by a standard
## modifier of the same effect. The order is defined and is the pipeline's own:
## the execution decides the base, and the effect's modifiers compose over what
## it decided.
func execute(
	_spec: GameplayEffectSpec, _target_asc: AbilitySystemComponent
) -> Dictionary[StringName, float]:
	push_error(
		"GAS_Engine: execute() called on the base GameplayExecutionCalculation. "
		+ "Override it in your specific child script."
	)
	return {}


## What this calculation decided, in full.
##
## The door the engine asks through. The default adapts whatever `execute()`
## returned, so a calculation written before this - which could only say "add
## this much to that" - keeps working exactly as it did, and one with more to
## say overrides this instead of `execute()`.
##
## More to say means: which of two same-named attributes it meant, whether its
## number multiplies rather than adds, effects to apply now that its numbers
## exist, and whether any of it should make a sound.
##
## Named apart from `execute()` rather than replacing its return type, which
## GDScript has no way to express: one function cannot answer with a Dictionary
## under one profile and an object under another. The engine only ever calls
## this one, so there is still a single path regardless of which a calculation
## overrode.
func execute_typed(
	spec: GameplayEffectSpec, target_asc: AbilitySystemComponent
) -> GameplayExecutionOutput:
	return GameplayExecutionOutput.from_deltas(execute(spec, target_asc))


## What this calculation decided, given everything it is allowed to know.
##
## The door the engine actually calls now. The default hands the two things
## an execution has always been given straight to `execute_typed()`, so every
## calculation written before this keeps working without knowing a context
## exists; one that needs scratch space between its own steps, the tags this
## application was handed, or its own scoped adjustments overrides this.
func execute_in(context: GameplayExecutionContext) -> GameplayExecutionOutput:
	return execute_typed(context.spec, context.target_asc)


## Adjustments that hold only while this calculation runs.
##
## For the arithmetic that would otherwise be either a mutation nobody asked
## for or a number buried inside a script: "against armour, if the attacker
## were 20% stronger" is a scoped modifier rather than a temporary buff on
## the attacker. Nothing declared here is registered as a contribution, and
## no other effect on the target ever sees it.
func scoped_modifiers() -> Array[GameplayExecutionScopedModifier]:
	return []


## Every attribute this calculation needs captured before execute() runs.
## `GameplayEffectSpec.prepare_captures()` registers and takes each one ahead
## of time, so a SOURCE or TARGET SNAPSHOT is already frozen by the time
## execute() asks `spec.resolve_capture()` for it - the default, empty, costs
## nothing and every execution calculation written before this existed
## still works.
func required_captures() -> Array[GameplayAttributeCaptureDefinition]:
	return []


## Which attributes execute() may write, for GameplayEffectQuery.modified_attribute
## and editor/debugger tooling - advisory metadata, never a second condition
## the evaluator enforces. The default, empty, costs nothing and every
## execution calculation written before this existed still works; a query
## asking about an attribute nobody declared simply never matches through it.
func declared_output_attributes() -> Array[StringName]:
	return []
#endregion
