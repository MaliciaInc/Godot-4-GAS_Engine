## Application, removal, refresh and cleanup of gameplay effects.
##
## The only place that commits what the evaluator staged: nothing is written
## until the whole transaction is OK. Removal drops contributions and
## recomposes rather than reversing a stored delta, which cannot express
## removing `+20` from a stack still holding `x1.5` and `x2`. Timing lives in
## GameplayEffectScheduler, state here.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayEffectRuntime extends RefCounted


## The facade this runtime emits through - the node other systems connect to.
var owner_asc: AbilitySystemComponent = null

var attributes: GameplayAttributeRuntime = null
var tags: GameplayTagRuntime = null

## Collaborators below are all wired alongside everything else in
## AbilitySystemComponent._wire_runtimes().
## Keeps a persistent contribution's LIVE-captured magnitude current.
var live_magnitudes: GameplayLiveMagnitudeRegistry = GameplayLiveMagnitudeRegistry.new()
## Orchestrates a spec's GameplayEffectComponent hooks: preflight, prepare,
## the applied/executed/removed notifications.
var components: GameplayEffectComponentRuntime = GameplayEffectComponentRuntime.new()
## Issues/resolves GameplayEffectHandle identities and answers
## GameplayEffectQuery lookups.
var handles: GameplayEffectHandleRegistry = GameplayEffectHandleRegistry.new()
## Owns inhibited/attached state and ongoing/removal tag-requirement
## reevaluation.
var inhibition: GameplayEffectInhibitionRuntime = GameplayEffectInhibitionRuntime.new()
## Owns stack identity, growth and the receipt swap a reapplication makes.
var stacking: GameplayEffectStackingRuntime = GameplayEffectStackingRuntime.new()
## Fires GameplayEffectAdditionalEffectsComponent's application/removal chains.
var chain: GameplayEffectChainRuntime = GameplayEffectChainRuntime.new()
## Bounded history of recent refusals, for the runtime debugger alone.
var refusal_log: GameplayEffectRefusalLog = GameplayEffectRefusalLog.new()

## Overflow_effects and Additional Effects are refused past this depth, so a
## cycle cannot recurse forever.
const MAX_EFFECT_CHAIN_DEPTH: int = 32

var _active: Array[ActiveGameplayEffect] = []
var _next_application_order: int = 0


#region Queries
## Every active effect, as a copy - a caller looping while removing must not
## see the live array skip an effect.
func active_effects() -> Array[ActiveGameplayEffect]:
	return _active.duplicate()


## The live array, for the scheduler alone: it walks backwards with a bounds
## guard so a self/other removal mid-walk cannot skip one, and runs every
## frame, so a copy here would be an allocation for nothing.
func live_active_effects() -> Array[ActiveGameplayEffect]:
	return _active


func active_count() -> int:
	return _active.size()


## AbilitySystemComponent.emit_tag_change() calls this after its own public
## F2 signals, for every tag change - the entry point for ongoing/removal
## reevaluation. See GameplayEffectInhibitionRuntime.
func on_owner_tags_changed() -> void:
	inhibition.on_owner_tags_changed()


## Remove `active` without detaching/emitting/clearing anything - for
## GameplayEffectPurgeTransaction alone, reversible until the incoming
## effect's own outcome is known.
func extract_active(active: ActiveGameplayEffect) -> int:
	var index: int = _active.find(active)
	if index >= 0:
		_active.remove_at(index)
	return index


## Undo extract_active: reinsert at `at_index`, clamped so a stale index
## from a since-shrunk registry still lands somewhere.
func restore_active(active: ActiveGameplayEffect, at_index: int) -> void:
	_active.insert(clampi(at_index, 0, _active.size()), active)


## The longest remaining duration among effects granting a tag, in seconds,
## for a cooldown sweep in the UI. INF when something grants it with no end -
## an INFINITE effect leaves `time_remaining` at 0.0, which used to read as a
## cooldown that already had rather than one that never expires. Turn-based
## effects are not counted: ask `tag_turns_remaining` for those instead. Nor is
## an inhibited one - `granted_tags` is the receipt uninhibiting puts back, not
## a claim the owner holds them, and reading it alone reported seconds, and
## forever, on a tag `has_tag` denied at that same instant. `state_attached`
## says the receipt is applied; `_is_immune_to` skips inhibited for the same
## reason.
func tag_duration_remaining(tag: StringName) -> float:
	var longest: float = 0.0
	for effect: ActiveGameplayEffect in _active:
		if not effect.state_attached or not effect.granted_tags.has(tag):
			continue
		var policy: GameplayEffect.DurationPolicy = effect.get_effect_def().policy
		if policy == GameplayEffect.DurationPolicy.INFINITE:
			return INF
		if policy == GameplayEffect.DurationPolicy.DURATION and effect.time_remaining > longest:
			longest = effect.time_remaining
	return longest


## The most turns left among turn-based effects granting a tag.
##
## The counterpart to `tag_duration_remaining`, and separate from it because
## turns and seconds are different units: a UI that mixed them would count down
## a three-turn debuff in seconds. Skips inhibited effects on the same grounds.
func tag_turns_remaining(tag: StringName) -> int:
	var longest: int = 0
	for effect: ActiveGameplayEffect in _active:
		if not effect.state_attached or not effect.granted_tags.has(tag) or effect.spec == null:
			continue
		if effect.get_effect_def().policy != GameplayEffect.DurationPolicy.TURN_BASED:
			continue
		longest = maxi(longest, effect.spec.remaining_turns)
	return longest
#endregion


#region Application
## Apply one spec to this ASC. Preflight (validate, then every component's
## can_apply) runs before purge/evaluation/any observable write; preparation
## is ephemeral and reversible; only then does the purge - itself reversible
## until this application's own outcome is known - and the evaluator run. A
## refusal at any stage is total.
func apply(spec: GameplayEffectSpec) -> GameplayEffectApplicationResult:
	if spec == null or spec.effect_def == null:
		return _refuse(GameplayEffectApplicationResult.Status.INVALID_SPEC, spec)

	if spec.chain_depth > MAX_EFFECT_CHAIN_DEPTH:
		return _refuse(GameplayEffectApplicationResult.Status.CHAIN_DEPTH_EXCEEDED, spec)

	if _is_immune_to(spec):
		return _refuse(GameplayEffectApplicationResult.Status.IMMUNE, spec)

	var effect: GameplayEffect = spec.effect_def
	if not components.validate_all(effect).is_ok():
		return _refuse(GameplayEffectApplicationResult.Status.INVALID_DEFINITION, spec)

	# Detected before the rest of preflight: which path this application
	# takes - fresh active effect or a join onto an existing stack - decides
	# nothing about whether it is a legal application, only what happens once
	# it is one.
	var stack_candidate: ActiveGameplayEffect = stacking.find_candidate(spec)

	var request: GameplayEffectComponentApplyRequest = components.build_request(spec, owner_asc)
	request.existing_active_effect = stack_candidate
	if not components.can_apply_all(request).is_allowed():
		return _refuse(GameplayEffectApplicationResult.Status.COMPONENT_REJECTED, spec)

	var prepared_states: Array[GameplayEffectComponentState] = []
	if not components.prepare_all(request, prepared_states):
		return _refuse(GameplayEffectApplicationResult.Status.COMPONENT_REJECTED, spec)
	spec.set_prepared_component_states(prepared_states)

	# Runs before evaluation so the new math sees the state it will land in,
	# reversible until the incoming effect's own outcome is known.
	var purge: GameplayEffectPurgeTransaction = GameplayEffectPurgeTransaction.begin(
		self, effect.get_remove_other_effects_query()
	)

	# TARGET+SNAPSHOT reads this post-purge state, never what stood before.
	if not spec.capture_target_attributes(owner_asc):
		purge.rollback()
		components.discard_for(spec)
		return _refuse(GameplayEffectApplicationResult.Status.EVALUATION_FAILED, spec)

	if stack_candidate != null:
		# GameplayEffectStackingRuntime logs its own refusals - report_refusal()
		# for an evaluation failure, refusal_log.record() directly for
		# STACK_OVERFLOW_DENIED - so this never has to know which one it got.
		var stack_result: GameplayEffectApplicationResult = stacking.apply_to_existing(stack_candidate, spec)
		if stack_result.is_ok():
			purge.commit()
		else:
			purge.rollback()
			components.discard_for(spec)
		return stack_result

	var order: int = _next_application_order
	var evaluation: GameplayEffectEvaluationResult = evaluate_spec(spec, order)
	if not evaluation.is_ok():
		purge.rollback()
		components.discard_for(spec)
		report_refusal(evaluation)
		return GameplayEffectApplicationResult.failure(
			GameplayEffectApplicationResult.Status.EVALUATION_FAILED,
			spec, evaluation.status, evaluation.error_attribute_name
		)

	purge.commit()
	_next_application_order += 1
	var active: ActiveGameplayEffect = _commit(spec, evaluation, order)
	return GameplayEffectApplicationResult.ok(spec, active)


## True if any uninhibited active effect's GameplayEffectImmunityComponent
## query matches `spec` - an inhibited immunity's owner is not currently in
## force, so it does not block.
func _is_immune_to(spec: GameplayEffectSpec) -> bool:
	for active: ActiveGameplayEffect in _active:
		if active.inhibited:
			continue
		var query: GameplayEffectQuery = active.get_effect_def().get_immunity_query()
		if query != null and query.matches_incoming(spec, owner_asc):
			return true
	return false


## Public: also called by GameplayEffectStackingRuntime, which needs to
## re-evaluate a spec against a stack's own application_order.
## `effect_handle` is null for the initial apply() evaluation (no handle
## exists yet for any effect type); a periodic tick or a stack reapplication
## passes the already-active effect's own handle.
func evaluate_spec(
	spec: GameplayEffectSpec, order: int, effect_handle: GameplayEffectHandle = null
) -> GameplayEffectEvaluationResult:
	var request: GameplayEffectEvaluator.Request = GameplayEffectEvaluator.Request.new()
	request.spec = spec
	request.attributes = attributes
	request.owner_asc = owner_asc
	request.application_order = order
	request.mode = _mode_for(spec)
	request.source_asc = spec.source_asc
	request.effect_handle = effect_handle
	return GameplayEffectEvaluator.evaluate(request)


## INSTANT and periodic effects transform the durable value once; DURATION
## and INFINITE register contributions - never both, or a periodic
## contributor would compound itself on every tick.
static func _mode_for(spec: GameplayEffectSpec) -> GameplayEffectEvaluator.Mode:
	if spec.effect_def.policy == GameplayEffect.DurationPolicy.INSTANT:
		return GameplayEffectEvaluator.Mode.BASE_MUTATION
	if spec.period > 0.0:
		return GameplayEffectEvaluator.Mode.BASE_MUTATION
	return GameplayEffectEvaluator.Mode.CONTRIBUTION


func report_refusal(evaluation: GameplayEffectEvaluationResult) -> void:
	refusal_log.record(GameplayEffectApplicationResult.failure(
		GameplayEffectApplicationResult.Status.EVALUATION_FAILED, null, evaluation.status, evaluation.error_attribute_name
	))
	if owner_asc == null:
		return
	owner_asc.effect_application_refused.emit(evaluation.status, evaluation.error_attribute_name)


## Builds and logs one refusal result in the same place, so it can never
## drift from what the caller actually returns.
func _refuse(status: GameplayEffectApplicationResult.Status, spec: GameplayEffectSpec) -> GameplayEffectApplicationResult:
	var result: GameplayEffectApplicationResult = GameplayEffectApplicationResult.failure(status, spec)
	refusal_log.record(result)
	return result


## Write everything the evaluation staged, in the one order that keeps the
## observable sequence honest: values first, then state, then notifications.
func _commit(
	spec: GameplayEffectSpec, evaluation: GameplayEffectEvaluationResult, order: int
) -> ActiveGameplayEffect:
	# Periodic writes nothing here - its modifiers are tick mutations, and
	# committing now would double-deal a DoT's first tick.
	var commits_base: bool = spec.period <= 0.0
	if commits_base:
		for staged: AttributeBaseMutation in evaluation.base_mutations:
			attributes.commit_base_write(staged)

	var active: ActiveGameplayEffect = ActiveGameplayEffect.new(spec, order)
	active.contributed_modifiers = evaluation.contributions
	active.stack_count = spec.stack_count

	var is_instant: bool = spec.effect_def.policy == GameplayEffect.DurationPolicy.INSTANT
	if is_instant:
		# Grants no tags and never persists: nothing to attach.
		attributes.add_contributions(evaluation.contributions)
	else:
		active.granted_tags = spec.get_granted_tags().duplicate()
		active.handle = handles.new_handle()
		handles.register(active)
		active.component_states = spec.prepared_component_states()
		_active.append(active)
		# Decides the starting inhibited/attached state - an ongoing_query
		# already unsatisfied registers inhibited from the start.
		inhibition.initialize(active)

	recompose_and_emit(spec)
	if commits_base:
		notify_execute_hooks(evaluation.base_mutations)

	if not is_instant and owner_asc != null:
		owner_asc.active_effect_added.emit(active)

	components.notify_applied(spec, active, owner_asc)
	play_cues(spec.effect_def.get_application_cue_tags(), spec, active.handle)
	dispatch_events(spec)
	notify_received(spec)
	chain.fire_on_application(spec)
	return active
#endregion


#region Removal
## Called by the scheduler when `active`'s own clock (duration or turns)
## reaches zero naturally - as opposed to `remove()` (gameplay code, or a
## removal query), which always takes the whole stack down regardless of
## stack_expiration_policy. See GameplayEffectStackingRuntime.expire().
func expire(active: ActiveGameplayEffect) -> void:
	stacking.expire(active)


## Remove one effect: drop its tags and contributions, fire its removal
## chain, then recompose and announce. `reason` decides which
## GameplayEffectAdditionalEffectsComponent arrays fire - see
## GameplayEffectChainRuntime.
func remove(
	active: ActiveGameplayEffect, reason: ActiveGameplayEffect.RemovalReason = ActiveGameplayEffect.RemovalReason.EXPLICIT
) -> void:
	if active == null or not _active.has(active):
		return
	_detach(active)
	_active.erase(active)
	recompose_and_emit(null)
	chain.fire_on_removal(active, reason)
	if owner_asc != null:
		owner_asc.active_effect_removed.emit(active)
		owner_asc.gameplay_effect_removal_finished.emit(active, reason)
	discard_receipts(active)


## Drop an effect's tags/contributions from the owner without recomposing.
## Separated from `remove()` so a bulk removal can detach everything first and
## recompose once. If already detached (inhibited), nothing was applied.
##
## The receipts themselves are not cleared here - see `discard_receipts()`.
func _detach(active: ActiveGameplayEffect) -> void:
	if active.state_attached:
		inhibition.set_attached(active, false)
	components.notify_removed(active.spec, active, owner_asc)
	handles.forget(active)


## Empty an effect's receipts, once every observer has been told it is gone.
##
## This ran inside `_detach()`, which happens before the removal is announced,
## so every subscriber of `active_effect_removed` and
## `gameplay_effect_removal_finished` was handed an effect that had already
## forgotten what it granted - and a GameplayEffectQuery filtering on
## `granted_tags` cannot match that, which is precisely what
## `AbilityTaskFactory.wait_gameplay_effect_removed_matching()` asks of it.
## Ordering only: the receipts are still emptied, just after the announcement.
func discard_receipts(active: ActiveGameplayEffect) -> void:
	active.granted_tags.clear()
	active.component_states.clear()
	active.contributed_modifiers.clear()


## Both bulk removals walk a snapshot, not the live registry.
##
## `remove()` may remove more than the effect it was given - its Additional
## Effects chain applies a child, and that child's remove-other-effects query
## purges a third - so the registry can shrink by several entries in one pass,
## and an index walk whose bounds were computed once reads past its end: "Out
## of bounds get index '1'", which stops a debug build at the debugger. The
## scheduler's walk guards against this; these two did not. A snapshot needs no
## guard: `remove()` ignores anything no longer registered. Reverse order kept.
func remove_effects_with_tag(tag: StringName) -> void:
	var snapshot: Array[ActiveGameplayEffect] = active_effects()
	for index: int in range(snapshot.size() - 1, -1, -1):
		if snapshot[index].granted_tags.has(tag):
			remove(snapshot[index])


func remove_effects_from_source(source_node: Node) -> void:
	if source_node == null:
		return
	var snapshot: Array[ActiveGameplayEffect] = active_effects()
	for index: int in range(snapshot.size() - 1, -1, -1):
		if snapshot[index].get_instigator() == source_node:
			remove(snapshot[index], ActiveGameplayEffect.RemovalReason.SOURCE_REMOVED)


## Tear down every active effect: detaches all first, empties the registry,
## then recomposes once. Idempotent - a second call emits nothing. Never
## fires an Additional Effects chain - ASC_CLEANUP is not a gameplay removal.
func cleanup() -> void:
	if _active.is_empty():
		return

	var removed: Array[ActiveGameplayEffect] = _active.duplicate()
	for active: ActiveGameplayEffect in removed:
		_detach(active)
	_active.clear()

	recompose_and_emit(null)
	if owner_asc != null:
		for active: ActiveGameplayEffect in removed:
			owner_asc.active_effect_removed.emit(active)
			owner_asc.gameplay_effect_removal_finished.emit(active, ActiveGameplayEffect.RemovalReason.ASC_CLEANUP)
	# Discarded whether or not there was an owner to announce it to: an ASC
	# torn down without one still has to leave its effects empty-handed.
	for active: ActiveGameplayEffect in removed:
		discard_receipts(active)
#endregion


#region Recomposition and notification
## Recompose every attribute once and emit one signal per attribute that
## moved. `source_spec` lets a listener tell what caused it; null for removal.
func recompose_and_emit(source_spec: GameplayEffectSpec) -> void:
	for mutation: AttributeMutationResult in attributes.recompose_all():
		if not mutation.current_changed:
			continue
		if owner_asc != null:
			owner_asc.emit_attribute_changed(mutation, source_spec)


## Fires post_gameplay_effect_execute for every base mutation the evaluation
## staged with execute_data - after recompose_and_emit, so a post hook always
## sees every attribute already committed and recomposed. Public: also called
## by GameplayEffectStackingRuntime after a reapplication, so a stack growth
## or refresh's own base mutations get the identical post-commit treatment
## without a second copy of this loop.
func notify_execute_hooks(mutations: Array[AttributeBaseMutation]) -> void:
	for staged: AttributeBaseMutation in mutations:
		if staged.execute_data != null:
			attributes.notify_gameplay_effect_execute(staged.execute_data)
#endregion


#region Cues and events
## Public: also called by GameplayEffectStackingRuntime after a reapplication,
## and by GameplayEffectInhibitionRuntime for a PERSISTENT binding's params.
## `effect_handle` is null for INSTANT (no handle exists) or when there is no
## active effect behind this call yet.
func play_cues(
	cue_tags: Array[StringName], spec: GameplayEffectSpec, effect_handle: GameplayEffectHandle = null
) -> void:
	if owner_asc == null:
		return
	for cue_tag: StringName in cue_tags:
		owner_asc.execute_cue(cue_params_for(cue_tag, spec, effect_handle))


func cue_params_for(
	cue_tag: StringName, spec: GameplayEffectSpec, effect_handle: GameplayEffectHandle = null
) -> GameplayCueParams:
	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = cue_tag
	params.instigator = spec.context.instigator if spec.context != null else null
	params.target = owner_asc.get_effect_target()
	params.context = spec.context
	params.effect_handle = effect_handle
	return params


func dispatch_events(spec: GameplayEffectSpec) -> void:
	if owner_asc == null:
		return
	owner_asc.dispatch_effect_events(spec)


func notify_received(spec: GameplayEffectSpec) -> void:
	if owner_asc == null:
		return
	owner_asc.effect_received.emit(owner_asc.find_source_asc(spec), spec)


## Play the cues and fire the events of one periodic tick. Called by the
## scheduler, which owns when a tick is due.
func run_periodic_tick(active: ActiveGameplayEffect) -> void:
	var spec: GameplayEffectSpec = active.spec
	var evaluation: GameplayEffectEvaluationResult = evaluate_spec(spec, active.application_order, active.handle)
	if not evaluation.is_ok():
		report_refusal(evaluation)
		return

	for staged: AttributeBaseMutation in evaluation.base_mutations:
		attributes.commit_base_write(staged)

	recompose_and_emit(spec)
	notify_execute_hooks(evaluation.base_mutations)
	components.notify_executed(spec, active, owner_asc)
	if owner_asc != null:
		owner_asc.gameplay_effect_executed.emit(spec, active)
	play_cues(spec.effect_def.get_periodic_cue_tags(), spec, active.handle)
	dispatch_events(spec)
#endregion
