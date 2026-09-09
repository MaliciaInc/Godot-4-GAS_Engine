## Base for one orthogonal piece of a GameplayEffect's behaviour: an
## authoring-time definition, never per-application state.
##
## Mirrors the problem Unreal 5.8's UGameplayEffectComponent solves - stop
## growing GameplayEffect as one bag of unrelated flags - with Resources and
## Godot-native lifecycle instead. A component never stores what happened
## during one application; that lives in GameplayEffectSpec,
## ActiveGameplayEffect, or a typed GameplayEffectComponentState tracked by
## component index. The same component Resource can appear on the same
## effect twice, and two applications share one definition but never one
## state - both are only possible because this stays inert.
##
## Every hook defaults to no-op/allow: a component overrides only the ones
## its behaviour needs.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@abstract
class_name GameplayEffectComponent extends Resource


## Whether two of this component may sit on one effect.
##
## True for most of them, because most are lists the runtime reads all of:
## two asset-tag components are two sets of tags and both count. False for
## the ones whose runtime accessor takes the first it finds - a second of
## those is not a second rule, it is a rule nobody reads, and an author who
## added one would be waiting for behaviour that never arrives.
##
## Asked of the component rather than listed by whoever is asking, so the
## editor and the runtime cannot disagree about which kind this is.
func allows_duplicates() -> bool:
	return true


## Whether this component's own authored fields are a legal definition.
## Called once per effect asset, never per application.
func validate_definition(
	_owner_effect: GameplayEffect
) -> GameplayEffectComponentValidationResult:
	return GameplayEffectComponentValidationResult.ok()


## Whether this component allows one application to proceed. Runs in the
## preflight stage, before purge, evaluation, or any observable write - a
## denial here means nothing happened at all.
func can_apply(_request: GameplayEffectComponentApplyRequest) -> GameplayEffectComponentDecision:
	return GameplayEffectComponentDecision.allow()


## Prepare whatever this component needs ready before commit, without
## mutating gameplay. May instantiate or probe Resources/Nodes ephemerally,
## but must not add or remove tags, register effects, write attributes, emit
## events, execute cues, or grant abilities - none of that is reversible, and
## preparation runs before the application's own outcome is known.
func prepare_application(
	_request: GameplayEffectComponentApplyRequest
) -> GameplayEffectComponentPreparationResult:
	return GameplayEffectComponentPreparationResult.ok()


## Undo whatever prepare_application() set up, because this application (or a
## component prepared after this one) was refused.
func discard_prepared(_state: GameplayEffectComponentState) -> void:
	pass


## Called when a spec is created from this effect, before any target is
## known. The default does nothing: most components only care once an
## application actually proceeds.
func on_spec_created(_request: GameplayEffectComponentApplyRequest) -> void:
	pass


## Called once, after a successful application's core state - attributes,
## tags, registration - has already been committed.
func on_effect_applied(_context: GameplayEffectComponentRuntimeContext) -> void:
	pass


## Called after a periodic tick's evaluation has committed.
func on_effect_executed(_context: GameplayEffectComponentRuntimeContext) -> void:
	pass


## Called when an active effect this component belongs to is removed, before
## its component state is discarded.
func on_effect_removed(_context: GameplayEffectComponentRemovalContext) -> void:
	pass
