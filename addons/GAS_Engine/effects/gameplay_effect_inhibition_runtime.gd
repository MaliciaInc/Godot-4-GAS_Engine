## Owns whether an active effect's receipt (granted tags, contributed
## modifiers) is actually attached to the tag runtime/aggregator, and
## reevaluates every active effect's ongoing/removal tag requirements
## whenever the owner's tags change.
##
## `ActiveGameplayEffect.granted_tags`/`contributed_modifiers` are the
## logical receipt of what an effect grants, kept even while inhibited; this
## runtime is the one place that decides whether that receipt is currently
## applied. Composed into GameplayEffectRuntime, same pattern as
## GameplayEffectHandleRegistry/GameplayLiveMagnitudeRegistry.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayEffectInhibitionRuntime extends RefCounted

## A cap on reevaluation passes, not on how many effects can be inhibited -
## an effect whose own granted tag falsifies its own ongoing_query would
## otherwise oscillate forever within one reevaluation.
const MAX_REQUIREMENT_REEVALUATION_PASSES: int = 64

var effects: GameplayEffectRuntime = null

## >0 while application/removal/inhibit/uninhibit is mid-mutation - a tag
## change from inside one of those (e.g. granting a tag mid-commit) only
## marks requirements dirty instead of reevaluating against a registry that
## is not yet coherent.
var _mutation_depth: int = 0
var _reevaluating: bool = false
var _dirty: bool = false


#region Mutation-depth guard
func begin_state_mutation() -> void:
	_mutation_depth += 1


func end_state_mutation() -> void:
	_mutation_depth = maxi(_mutation_depth - 1, 0)
	if _mutation_depth == 0 and _dirty:
		_reevaluate()
#endregion


#region Tag-driven reevaluation
## Called by AbilitySystemComponent.emit_tag_change(), after its own public
## F2 signals, for every tag change - not only ones caused by an effect.
func on_owner_tags_changed() -> void:
	if _mutation_depth > 0:
		_dirty = true
		return
	_reevaluate()


## 1. reentrant call while already reevaluating -> mark dirty, return.
## 2. snapshot active handles, evaluate, apply transitions.
## 3. repeat while dirty, until stable or the pass cap is hit.
func _reevaluate() -> void:
	if _reevaluating:
		_dirty = true
		return
	_reevaluating = true
	begin_state_mutation()

	var passes: int = 0
	var converged: bool = false
	var last_pass_changed: Array[ActiveGameplayEffect] = []
	while passes < MAX_REQUIREMENT_REEVALUATION_PASSES:
		_dirty = false
		passes += 1
		last_pass_changed = _reevaluate_one_pass()
		if last_pass_changed.is_empty() and not _dirty:
			converged = true
			break

	if not converged:
		_freeze_as_inhibited_and_diagnose(last_pass_changed)
		# Stop for this call no matter what triggered dirty during the last
		# pass - unwinding end_state_mutation() below must not immediately
		# restart a reevaluation that just proved it cannot converge.
		_dirty = false

	effects.recompose_and_emit(null)
	_reevaluating = false
	end_state_mutation()


## One pass over a snapshot of active effects. Returns every effect that
## transitioned, so the caller knows whether another pass could be needed -
## and, if the cycle never stabilizes, exactly which ones were oscillating.
func _reevaluate_one_pass() -> Array[ActiveGameplayEffect]:
	var changed: Array[ActiveGameplayEffect] = []
	for active: ActiveGameplayEffect in effects.active_effects():
		if _apply_removal_if_due(active):
			changed.append(active)
			continue
		if _apply_ongoing_transition(active):
			changed.append(active)
	return changed


func _apply_removal_if_due(active: ActiveGameplayEffect) -> bool:
	var query: GameplayTagQuery = active.get_effect_def().get_removal_query()
	if query == null or query.is_empty():
		return false
	if effects.owner_asc == null or not query.matches_runtime(effects.owner_asc.tags):
		return false
	effects.remove(active)
	return true


func _apply_ongoing_transition(active: ActiveGameplayEffect) -> bool:
	var satisfied: bool = _ongoing_satisfied(active)
	if active.inhibited == not satisfied:
		return false
	set_inhibited(active, not satisfied)
	return true


func _ongoing_satisfied(active: ActiveGameplayEffect) -> bool:
	var query: GameplayTagQuery = active.get_effect_def().get_ongoing_query()
	if query == null or query.is_empty():
		return true
	return effects.owner_asc != null and query.matches_runtime(effects.owner_asc.tags)


## A cycle that never stabilizes forces every still-oscillating effect
## inhibited, regardless of which state the final pass happened to leave it
## in - flip-flopping ends on whichever phase the pass cap lands on, and
## that parity is not a fact about the effect. Never removed, never toggled
## again this call. Inhibited is the fail-safe: an effect that cannot be
## proven ongoing does not act as if it were.
func _freeze_as_inhibited_and_diagnose(implicated: Array[ActiveGameplayEffect]) -> void:
	push_warning(
		"GAS_Engine: ongoing-requirement reevaluation did not converge within "
		+ str(MAX_REQUIREMENT_REEVALUATION_PASSES) + " passes; leaving affected effects inhibited."
	)
	var still_active: Array[ActiveGameplayEffect] = effects.active_effects()
	for active: ActiveGameplayEffect in implicated:
		if not still_active.has(active):
			continue
		set_inhibited(active, true)
		if effects.owner_asc != null and active.handle != null:
			effects.owner_asc.effect_requirement_cycle_aborted.emit(active.handle)
#endregion


#region Inhibit/uninhibit
func set_inhibited(active: ActiveGameplayEffect, new_inhibited: bool) -> void:
	if active.inhibited == new_inhibited:
		return
	active.inhibited = new_inhibited
	set_attached(active, not new_inhibited)
	if effects.owner_asc != null and active.handle != null:
		effects.owner_asc.active_effect_inhibition_changed.emit(active.handle, new_inhibited)
#endregion


#region Attach/detach - the single owner of ActiveGameplayEffect.state_attached
## Called once, right after `active` is registered, to decide its starting
## inhibited/attached state from the target's current tags.
func initialize(active: ActiveGameplayEffect) -> void:
	active.state_attached = false
	var satisfied: bool = _ongoing_satisfied(active)
	active.inhibited = not satisfied
	if satisfied:
		set_attached(active, true)


## attached -> false drops the receipt from the aggregator/tag runtime
## without clearing it; false -> true re-adds the same receipt unchanged.
## Idempotent either direction.
func set_attached(active: ActiveGameplayEffect, attached: bool) -> void:
	if active.state_attached == attached:
		return
	begin_state_mutation()
	if attached:
		_attach(active)
	else:
		_detach(active)
	active.state_attached = attached
	effects.recompose_and_emit(active.spec)
	end_state_mutation()


func _attach(active: ActiveGameplayEffect) -> void:
	for tag: StringName in active.granted_tags:
		var change: GameplayTagRuntime.Change = effects.tags.add(tag)
		if effects.owner_asc != null:
			effects.owner_asc.emit_tag_change(tag, change, effects.tags.count(tag))
	effects.attributes.add_contributions(active.contributed_modifiers)
	if GameplayEffectRuntime._mode_for(active.spec) == GameplayEffectEvaluator.Mode.CONTRIBUTION:
		effects.live_magnitudes.create_bindings_for(active)
	_resume_periodic_clock(active)
	_activate_persistent_cues(active)


func _detach(active: ActiveGameplayEffect) -> void:
	for tag: StringName in active.granted_tags:
		var change: GameplayTagRuntime.Change = effects.tags.remove(tag)
		if effects.owner_asc != null:
			effects.owner_asc.emit_tag_change(tag, change, effects.tags.count(tag))
	effects.live_magnitudes.disconnect_bindings_for(active)
	effects.attributes.remove_contributions_of(active.application_order)
	_deactivate_persistent_cues(active)


## "Entra uninhibited" - a fresh lifecycle activation every time this runs,
## never reusing a handle from a previous attach: uninhibiting always
## appends new ones onto an array `_deactivate_persistent_cues` already
## emptied.
func _activate_persistent_cues(active: ActiveGameplayEffect) -> void:
	if effects.owner_asc == null:
		return
	for binding: GameplayCueBinding in active.get_effect_def().get_persistent_cue_bindings():
		var params: GameplayCueParams = effects.cue_params_for(binding.cue_tag, active.spec, active.handle)
		active.persistent_cue_handles.append(effects.owner_asc.activate_persistent_cue(params))


## Ends and pools every persistent cue this effect is currently running,
## whether from an inhibit or the effect's own removal - `_detach()` is the
## one place either reaches. Paired by index with the bindings that started
## them, which `_activate_persistent_cues` builds in the same order.
func _deactivate_persistent_cues(active: ActiveGameplayEffect) -> void:
	if effects.owner_asc != null:
		var bindings: Array[GameplayCueBinding] = active.get_effect_def().get_persistent_cue_bindings()
		for i: int in active.persistent_cue_handles.size():
			var tag: StringName = bindings[i].cue_tag if i < bindings.size() else &""
			var params: GameplayCueParams = effects.cue_params_for(tag, active.spec, active.handle)
			effects.owner_asc.deactivate_persistent_cue(active.persistent_cue_handles[i], params)
	active.persistent_cue_handles.clear()


## Applies the effect's PeriodInhibitionPolicy at the moment of reattaching.
## Ticks owed while inhibited were already skipped by GameplayEffectScheduler
## without running - this only handles the catch-up/reset on the way back.
##
## Both restarting policies say the same thing to the clock, so both ask
## ActiveGameplayEffect.restart_period_clock() rather than spelling it out.
## The stacking runtime spelled it out too, and spelled it wrong.
func _resume_periodic_clock(active: ActiveGameplayEffect) -> void:
	if not active.is_periodic():
		return
	match active.get_effect_def().period_inhibition_policy:
		GameplayEffect.PeriodInhibitionPolicy.EXECUTE_IMMEDIATELY_ON_UNINHIBIT:
			if active.missed_tick_while_inhibited:
				effects.run_periodic_tick(active)
			active.restart_period_clock()
		GameplayEffect.PeriodInhibitionPolicy.RESET_PERIOD_ON_UNINHIBIT:
			active.restart_period_clock()
		GameplayEffect.PeriodInhibitionPolicy.SKIP_MISSED_TICKS:
			pass
#endregion
