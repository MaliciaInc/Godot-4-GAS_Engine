## Stack identity, growth, and the receipt swap a reapplication makes: the
## authoritative snapshot always becomes the most recent application copy,
## never an incremental delta on top of the old one.
##
## Composed into GameplayEffectRuntime, same pattern as
## GameplayEffectHandleRegistry/GameplayEffectInhibitionRuntime.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectStackingRuntime extends RefCounted

var effects: GameplayEffectRuntime = null


## The active effect `spec` joins under its effect_def's stacking_type, or
## null if stacking_type is NONE or nothing matching is active yet.
## AGGREGATE_BY_SOURCE requires a resolved, matching source_asc - a spec with
## no source never aggregates by source, since there is no identity to match.
func find_candidate(spec: GameplayEffectSpec) -> ActiveGameplayEffect:
	var effect: GameplayEffect = spec.effect_def
	if effect.stacking_type == GameplayEffect.StackingType.NONE:
		return null
	for active: ActiveGameplayEffect in effects.active_effects():
		if active.get_effect_def() != effect:
			continue
		if effect.stacking_type == GameplayEffect.StackingType.AGGREGATE_BY_SOURCE:
			if spec.source_asc == null or active.spec.source_asc != spec.source_asc:
				continue
		return active
	return null


## True if `existing` has room for one more application under its effect's
## stack_limit_count. <= 0 is unlimited.
func can_grow(existing: ActiveGameplayEffect) -> bool:
	var limit: int = existing.get_effect_def().stack_limit_count
	return limit <= 0 or existing.stack_count < limit


## Replaces `existing`'s authoritative snapshot with `spec` and `new_count`:
## drops the old receipt from the aggregator, swaps spec/contributions/tags/
## component states/stack_count, then re-applies the new receipt if the
## effect was actually attached. Clocks are the caller's decision - a
## reapplication restarts them per stack_duration_refresh_policy/
## stack_period_reset_policy, an expiration always restarts them - so this
## never touches time_remaining/elapsed_time itself.
## `evaluation` was computed with `spec.stack_count` already set to
## `new_count`, so its contributions are already scaled correctly.
func replace_stack_state(
	existing: ActiveGameplayEffect,
	spec: GameplayEffectSpec,
	evaluation: GameplayEffectEvaluationResult,
	new_count: int
) -> void:
	var was_attached: bool = existing.state_attached
	if was_attached:
		effects.attributes.remove_contributions_of(existing.application_order)
		effects.live_magnitudes.disconnect_bindings_for(existing)
	if spec.period <= 0.0:
		for staged: AttributeBaseMutation in evaluation.base_mutations:
			effects.attributes.commit_base_write(staged)

	existing.spec = spec
	existing.stack_count = new_count
	existing.contributed_modifiers = evaluation.contributions
	existing.granted_tags = spec.get_granted_tags().duplicate()
	existing.component_states = spec.prepared_component_states()

	if was_attached:
		effects.attributes.add_contributions(evaluation.contributions)
		if GameplayEffectRuntime._mode_for(spec) == GameplayEffectEvaluator.Mode.CONTRIBUTION:
			effects.live_magnitudes.create_bindings_for(existing)


## Restarts `existing`'s duration/period clocks per its effect's
## stack_duration_refresh_policy/stack_period_reset_policy - the successful-
## reapplication path only.
func refresh_clocks_on_reapplication(existing: ActiveGameplayEffect) -> void:
	var effect: GameplayEffect = existing.get_effect_def()
	if (
		effect.stack_duration_refresh_policy == GameplayEffect.StackDurationRefreshPolicy.ON_SUCCESSFUL_APPLICATION
		and effect.policy == GameplayEffect.DurationPolicy.DURATION
	):
		existing.time_remaining = existing.spec.duration
	if (
		effect.stack_period_reset_policy == GameplayEffect.StackPeriodResetPolicy.ON_SUCCESSFUL_APPLICATION
		and existing.is_periodic()
	):
		reset_period_clock(existing)


## Unconditional period-clock reset, for both the reapplication path above
## and expiration's own always-restart duration semantics.
func reset_period_clock(existing: ActiveGameplayEffect) -> void:
	existing.elapsed_time = 0.0
	existing.completed_ticks = 0
	existing.period_origin_elapsed = 0.0
	existing.missed_tick_while_inhibited = false


#region Reapplication onto an existing stack
## `existing` already matched `spec` by stack identity (find_candidate).
## Grows the stack if there is room, otherwise hands off to overflow
## handling. Called from GameplayEffectRuntime.apply(), between the purge
## and the normal fresh-application path.
func apply_to_existing(existing: ActiveGameplayEffect, spec: GameplayEffectSpec) -> GameplayEffectApplicationResult:
	if can_grow(existing):
		return _grow(existing, spec)
	return _handle_overflow(existing, spec)


func _grow(existing: ActiveGameplayEffect, spec: GameplayEffectSpec) -> GameplayEffectApplicationResult:
	var old_count: int = existing.stack_count
	var new_count: int = old_count + 1
	var evaluation: GameplayEffectEvaluationResult = _evaluate_at(spec, existing, new_count)
	if not evaluation.is_ok():
		return _evaluation_failure(spec, evaluation)

	replace_stack_state(existing, spec, evaluation, new_count)
	refresh_clocks_on_reapplication(existing)
	_finish_reapplication(existing, spec)
	if effects.owner_asc != null and existing.handle != null:
		effects.owner_asc.active_effect_stack_changed.emit(existing.handle, old_count, new_count)
	return GameplayEffectApplicationResult.ok(spec, existing)


## `existing` is already at its stack_limit_count. Overflow always signals
## and fires overflow_effects; deny_overflow_application refuses the
## application outright instead of accepting it as a non-growing refresh;
## clear_stack_on_overflow removes the whole stack afterward, independently
## of that decision.
func _handle_overflow(existing: ActiveGameplayEffect, spec: GameplayEffectSpec) -> GameplayEffectApplicationResult:
	var effect: GameplayEffect = spec.effect_def
	if effects.owner_asc != null and existing.handle != null:
		effects.owner_asc.active_effect_stack_overflowed.emit(existing.handle)
	_apply_overflow_effects(effect, spec)

	var result: GameplayEffectApplicationResult
	if effect.deny_overflow_application:
		result = GameplayEffectApplicationResult.failure(GameplayEffectApplicationResult.Status.STACK_OVERFLOW_DENIED, spec)
	else:
		result = _refresh_without_growing(existing, spec)

	if effect.clear_stack_on_overflow and effects.active_effects().has(existing):
		effects.remove(existing, ActiveGameplayEffect.RemovalReason.STACK_OVERFLOW)
	return result


## Accepted at the ceiling: the receipt/clocks still update per policy, the
## count does not. Emits `active_effect_refreshed`, never a stack-changed
## pair with an unchanged count.
func _refresh_without_growing(existing: ActiveGameplayEffect, spec: GameplayEffectSpec) -> GameplayEffectApplicationResult:
	var count: int = existing.stack_count
	var evaluation: GameplayEffectEvaluationResult = _evaluate_at(spec, existing, count)
	if not evaluation.is_ok():
		return _evaluation_failure(spec, evaluation)

	replace_stack_state(existing, spec, evaluation, count)
	refresh_clocks_on_reapplication(existing)
	_finish_reapplication(existing, spec)
	if effects.owner_asc != null:
		effects.owner_asc.active_effect_refreshed.emit(existing)
	return GameplayEffectApplicationResult.ok(spec, existing)


## Applied to the same target as the incoming spec, with source/context
## derived from it. A child's own failure - refusal, or CHAIN_DEPTH_EXCEEDED
## once nesting runs too deep - never corrupts the stack that overflowed.
func _apply_overflow_effects(effect: GameplayEffect, incoming_spec: GameplayEffectSpec) -> void:
	if effects.owner_asc == null:
		return
	for overflow_effect: GameplayEffect in effect.overflow_effects:
		if overflow_effect == null:
			continue
		var instigator: Node = incoming_spec.context.instigator if incoming_spec.context != null else null
		var child: GameplayEffectSpec = GameplayEffectSpec.new(
			overflow_effect, GameplayEffectContext.new(instigator), incoming_spec.level
		)
		child.source_asc = incoming_spec.source_asc
		child.chain_depth = incoming_spec.chain_depth + 1
		effects.owner_asc.apply_effect_spec_result(child)
#endregion


#region Expiration
## Called by the scheduler when `active`'s own clock (duration or turns)
## reaches zero naturally - as opposed to GameplayEffectRuntime.remove()
## (gameplay code, or a removal query), which always takes the whole stack
## down regardless of stack_expiration_policy.
func expire(active: ActiveGameplayEffect) -> void:
	var effect: GameplayEffect = active.get_effect_def()
	if effect.stacking_type == GameplayEffect.StackingType.NONE:
		effects.remove(active, ActiveGameplayEffect.RemovalReason.NATURAL_EXPIRATION)
		return
	match effect.stack_expiration_policy:
		GameplayEffect.StackExpirationPolicy.CLEAR_ENTIRE_STACK:
			effects.remove(active, ActiveGameplayEffect.RemovalReason.NATURAL_EXPIRATION)
		GameplayEffect.StackExpirationPolicy.REMOVE_SINGLE_STACK_AND_REFRESH_DURATION:
			if active.stack_count <= 1:
				effects.remove(active, ActiveGameplayEffect.RemovalReason.NATURAL_EXPIRATION)
			else:
				_settle_expiring(active, active.stack_count - 1)
		GameplayEffect.StackExpirationPolicy.REFRESH_DURATION:
			_settle_expiring(active, active.stack_count)


## Re-evaluates `active`'s own spec at `new_count` and always restarts its
## clocks - unlike a successful reapplication, which only does so per
## stack_duration_refresh_policy/stack_period_reset_policy, expiration
## restarts them unconditionally: that is what "the clock ran out and the
## stack survived" means.
func _settle_expiring(active: ActiveGameplayEffect, new_count: int) -> void:
	var old_count: int = active.stack_count
	var evaluation: GameplayEffectEvaluationResult = _evaluate_at(active.spec, active, new_count)
	if not evaluation.is_ok():
		effects.report_refusal(evaluation)
		return

	replace_stack_state(active, active.spec, evaluation, new_count)
	var effect: GameplayEffect = active.get_effect_def()
	if effect.policy == GameplayEffect.DurationPolicy.DURATION:
		active.time_remaining = active.spec.duration
	elif effect.policy == GameplayEffect.DurationPolicy.TURN_BASED:
		active.spec.remaining_turns = effect.duration_turns
	if active.is_periodic():
		reset_period_clock(active)

	effects.recompose_and_emit(active.spec)
	if new_count != old_count and effects.owner_asc != null and active.handle != null:
		effects.owner_asc.active_effect_stack_changed.emit(active.handle, old_count, new_count)
#endregion


#region Shared helpers
## `spec.stack_count` is set before evaluating so factor_in_stack_count
## scales the resolved magnitude by the count this application would settle
## at - grown, unchanged at the ceiling, or one fewer after expiration.
func _evaluate_at(spec: GameplayEffectSpec, existing: ActiveGameplayEffect, count: int) -> GameplayEffectEvaluationResult:
	spec.stack_count = count
	return effects.evaluate_spec(spec, existing.application_order)


func _evaluation_failure(
	spec: GameplayEffectSpec, evaluation: GameplayEffectEvaluationResult
) -> GameplayEffectApplicationResult:
	effects.report_refusal(evaluation)
	return GameplayEffectApplicationResult.failure(
		GameplayEffectApplicationResult.Status.EVALUATION_FAILED,
		spec, evaluation.status, evaluation.error_attribute_name
	)


func _finish_reapplication(existing: ActiveGameplayEffect, spec: GameplayEffectSpec) -> void:
	effects.recompose_and_emit(spec)
	effects.components.notify_applied(spec, existing, effects.owner_asc)
	effects.play_cues(spec.effect_def.application_cue_tags, spec)
	effects.dispatch_events(spec)
	effects.notify_received(spec)
	effects.chain.fire_on_application(spec)
#endregion
