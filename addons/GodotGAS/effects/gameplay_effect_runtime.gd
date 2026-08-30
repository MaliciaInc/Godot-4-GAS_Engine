## Application, removal, refresh and cleanup of gameplay effects.
##
## This is the only place that commits what the evaluator staged. Nothing is
## written until the whole transaction is OK, so an effect whose second
## attribute divides by zero changes no attribute, registers no active effect,
## grants no tag, plays no cue and dispatches no event.
##
## Removal drops contributions and recomposes. It never reverses a stored delta,
## because a delta cannot express the removal of `+20` from a stack that still
## holds `x1.5` and `x2`.
##
## Timing lives in GameplayEffectScheduler; this file owns state, not clocks.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectRuntime extends RefCounted


## The facade this runtime emits through. Signals belong to the ASC because it
## is the node other systems connect to.
var owner_asc: AbilitySystemComponent = null

var attributes: GameplayAttributeRuntime = null
var tags: GameplayTagRuntime = null

var _active: Array[ActiveGameplayEffect] = []
var _next_application_order: int = 0


#region Queries
## Every active effect, as a copy.
##
## A copy because a caller that loops over this while removing is writing
## the most ordinary code there is, and handing back the live array made
## that loop skip every other effect.
func active_effects() -> Array[ActiveGameplayEffect]:
	return _active.duplicate()


## The live array, for the scheduler alone.
##
## It walks backwards with a bounds guard precisely so an effect removing
## itself or another during the walk cannot skip one, and it runs every
## frame, so a copy per update would be an allocation for nothing. Nobody
## else should hold this: the guarantee comes from how it is iterated, not
## from the array.
func live_active_effects() -> Array[ActiveGameplayEffect]:
	return _active


func active_count() -> int:
	return _active.size()


## Remove `active` from the registry without detaching or emitting
## anything, and without clearing what it held. For
## GameplayEffectPurgeTransaction alone, which manages tags and
## contributions itself so it can capture exactly what changed and stay
## reversible until the incoming effect's outcome is known.
func extract_active(active: ActiveGameplayEffect) -> int:
	var index: int = _active.find(active)
	if index >= 0:
		_active.remove_at(index)
	return index


## Undo extract_active: put `active` back at `at_index`, clamped to the
## current size so a stale index from a registry that has since shrunk
## still lands somewhere rather than erroring.
func restore_active(active: ActiveGameplayEffect, at_index: int) -> void:
	_active.insert(clampi(at_index, 0, _active.size()), active)


## The longest remaining duration among effects granting a tag, in seconds, for
## a cooldown sweep in the UI.
##
## INF when something grants it with no end. `time_remaining` is only ever set
## for a DURATION effect, so an INFINITE one used to leave this at 0.0 and the
## sweep read a cooldown that never expires as one that already had.
##
## Turn-based effects are not counted: their clock runs in turns, and answering
## a question about seconds with a number of turns is worse than answering 0.
## Ask `tag_turns_remaining` for those.
func tag_duration_remaining(tag: StringName) -> float:
	var longest: float = 0.0
	for effect: ActiveGameplayEffect in _active:
		if not effect.granted_tags.has(tag):
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
## a three-turn debuff in seconds.
func tag_turns_remaining(tag: StringName) -> int:
	var longest: int = 0
	for effect: ActiveGameplayEffect in _active:
		if not effect.granted_tags.has(tag) or effect.spec == null:
			continue
		if effect.get_effect_def().policy != GameplayEffect.DurationPolicy.TURN_BASED:
			continue
		longest = maxi(longest, effect.spec.remaining_turns)
	return longest
#endregion


#region Application
## Apply one spec to this ASC. Returns the active effect, or null on refusal.
##
## A refusal is total: nothing observable happened.
func apply(spec: GameplayEffectSpec) -> ActiveGameplayEffect:
	if spec == null or spec.effect_def == null:
		return null

	var effect: GameplayEffect = spec.effect_def
	if tags.has_any(effect.application_ignore_tags):
		return null
	if not effect.application_required_tags.is_empty():
		if not tags.has_all(effect.application_required_tags):
			return null

	# The cleanser runs before evaluation so the new math sees the state it
	# will actually land in. It stays reversible until the incoming effect's
	# own outcome is known: "a refusal is total" applies to the purge too.
	var purge: GameplayEffectPurgeTransaction = GameplayEffectPurgeTransaction.begin(
		self, effect.remove_effects_with_tags
	)

	# A TARGET+SNAPSHOT capture reads this same post-purge state - what
	# evaluation itself is about to see - never what stood before the purge.
	if not spec.capture_target_attributes(owner_asc):
		purge.rollback()
		return null

	var refreshed: ActiveGameplayEffect = _try_refresh(spec)
	if refreshed != null:
		purge.commit()
		return refreshed

	var order: int = _next_application_order
	var evaluation: GameplayEffectEvaluationResult = _evaluate(spec, order)
	if not evaluation.is_ok():
		purge.rollback()
		_report_refusal(evaluation)
		return null

	purge.commit()
	_next_application_order += 1
	return _commit(spec, evaluation, order)


func _evaluate(spec: GameplayEffectSpec, order: int) -> GameplayEffectEvaluationResult:
	var request: GameplayEffectEvaluator.Request = GameplayEffectEvaluator.Request.new()
	request.spec = spec
	request.attributes = attributes
	request.owner_asc = owner_asc
	request.application_order = order
	request.mode = _mode_for(spec)
	request.source_asc = spec.source_asc
	return GameplayEffectEvaluator.evaluate(request)


## INSTANT and periodic effects transform the durable value once. DURATION and
## INFINITE register contributions. One effect cannot be both,
## because a periodic contributor would compound itself on every tick.
static func _mode_for(spec: GameplayEffectSpec) -> GameplayEffectEvaluator.Mode:
	if spec.effect_def.policy == GameplayEffect.DurationPolicy.INSTANT:
		return GameplayEffectEvaluator.Mode.BASE_MUTATION
	if spec.period > 0.0:
		return GameplayEffectEvaluator.Mode.BASE_MUTATION
	return GameplayEffectEvaluator.Mode.CONTRIBUTION


func _report_refusal(evaluation: GameplayEffectEvaluationResult) -> void:
	if owner_asc == null:
		return
	owner_asc.effect_application_refused.emit(evaluation.status, evaluation.error_attribute_name)


## Write everything the evaluation staged, in the one order that keeps the
## observable sequence honest: values first, then state, then notifications.
func _commit(
	spec: GameplayEffectSpec, evaluation: GameplayEffectEvaluationResult, order: int
) -> ActiveGameplayEffect:
	# A periodic effect writes nothing on application. Its modifiers are tick
	# mutations, and committing them here would pay a tick at t=0 that the
	# clock never owed - every DoT would deal one extra instance of damage.
	# The evaluation still ran, so a broken periodic effect is still refused.
	if spec.period <= 0.0:
		for staged: AttributeBaseMutation in evaluation.base_mutations:
			attributes.commit_base_write(staged)

	var active: ActiveGameplayEffect = ActiveGameplayEffect.new(spec, order)
	active.contributed_modifiers = evaluation.contributions
	attributes.add_contributions(evaluation.contributions)

	var is_instant: bool = spec.effect_def.policy == GameplayEffect.DurationPolicy.INSTANT
	if not is_instant:
		# Instant effects grant no tags: they leave nothing behind to hold one.
		for tag: StringName in spec.effect_def.granted_tags:
			_grant_tag(active, tag)
		_active.append(active)

	recompose_and_emit(spec)

	if not is_instant and owner_asc != null:
		owner_asc.active_effect_added.emit(active)

	_play_cues(spec.effect_def.application_cue_tags, spec)
	_dispatch_events(spec)
	_notify_received(spec)
	return active


func _grant_tag(active: ActiveGameplayEffect, tag: StringName) -> void:
	var change: GameplayTagRuntime.Change = tags.add(tag)
	active.granted_tags.append(tag)
	if owner_asc != null:
		owner_asc.emit_tag_change(tag, change, tags.count(tag))
#endregion


#region Refresh
## Reapply an effect whose stacking policy is REFRESH_DURATION.
##
## The logical instance survives: its contributions and snapshot are replaced by
## the new application's, and its clock restarts. It emits `active_effect_refreshed`
## once and does NOT emit a remove/add pair, because a UI that sees one would
## tear down and rebuild an icon that never actually went away. The granted tag
## refcount stays at one for the same reason.
func _try_refresh(spec: GameplayEffectSpec) -> ActiveGameplayEffect:
	var effect: GameplayEffect = spec.effect_def
	if effect.stacking_policy != GameplayEffect.StackingPolicy.REFRESH_DURATION:
		return null
	if not _is_refreshable_policy(effect.policy):
		return null

	var existing: ActiveGameplayEffect = _find_active_of(effect)
	if existing == null:
		return null

	var evaluation: GameplayEffectEvaluationResult = _evaluate(spec, existing.application_order)
	if not evaluation.is_ok():
		_report_refusal(evaluation)
		return null

	attributes.remove_contributions_of(existing.application_order)
	for staged: AttributeBaseMutation in evaluation.base_mutations:
		attributes.commit_base_write(staged)

	existing.spec = spec
	existing.contributed_modifiers = evaluation.contributions
	existing.elapsed_time = 0.0
	existing.completed_ticks = 0
	if effect.policy == GameplayEffect.DurationPolicy.DURATION:
		existing.time_remaining = spec.duration
	attributes.add_contributions(evaluation.contributions)

	recompose_and_emit(spec)
	if owner_asc != null:
		owner_asc.active_effect_refreshed.emit(existing)
	_play_cues(effect.application_cue_tags, spec)
	_dispatch_events(spec)
	_notify_received(spec)
	return existing


static func _is_refreshable_policy(policy: GameplayEffect.DurationPolicy) -> bool:
	return (
		policy == GameplayEffect.DurationPolicy.DURATION
		or policy == GameplayEffect.DurationPolicy.TURN_BASED
	)


func _find_active_of(effect: GameplayEffect) -> ActiveGameplayEffect:
	for active: ActiveGameplayEffect in _active:
		if active.get_effect_def() == effect:
			return active
	return null
#endregion


#region Removal
## Remove one effect: drop its tags and contributions, then recompose.
func remove(active: ActiveGameplayEffect) -> void:
	if active == null or not _active.has(active):
		return
	_detach(active)
	_active.erase(active)
	recompose_and_emit(null)
	if owner_asc != null:
		owner_asc.active_effect_removed.emit(active)


## Drop an effect's tags and contributions without recomposing.
##
## Separated so a bulk removal can detach everything first and recompose once.
## Recomposing per effect while the others are still registered is how a cleanup
## ends up emitting a cascade of intermediate values nobody ever had.
func _detach(active: ActiveGameplayEffect) -> void:
	for tag: StringName in active.granted_tags:
		var change: GameplayTagRuntime.Change = tags.remove(tag)
		if owner_asc != null:
			owner_asc.emit_tag_change(tag, change, tags.count(tag))
	active.granted_tags.clear()
	attributes.remove_contributions_of(active.application_order)
	active.contributed_modifiers.clear()


func remove_effects_with_tag(tag: StringName) -> void:
	for index: int in range(_active.size() - 1, -1, -1):
		if _active[index].granted_tags.has(tag):
			remove(_active[index])


func remove_effects_from_source(source_node: Node) -> void:
	if source_node == null:
		return
	for index: int in range(_active.size() - 1, -1, -1):
		if _active[index].get_instigator() == source_node:
			remove(_active[index])


## Tear down every active effect.
##
## Detaches all of them first, empties the registry, then recomposes once from
## base plus an empty stack. Idempotent: a second call on an already-clean
## runtime emits nothing at all.
func cleanup() -> void:
	if _active.is_empty():
		return

	var removed: Array[ActiveGameplayEffect] = _active.duplicate()
	for active: ActiveGameplayEffect in removed:
		_detach(active)
	_active.clear()

	recompose_and_emit(null)
	if owner_asc == null:
		return
	for active: ActiveGameplayEffect in removed:
		owner_asc.active_effect_removed.emit(active)
#endregion


#region Recomposition and notification
## Recompose every attribute once and emit one signal per attribute that moved.
##
## `source_spec` is passed through to `attribute_changed` so a listener can tell
## what caused the change. Null for a removal, which has no spec.
func recompose_and_emit(source_spec: GameplayEffectSpec) -> void:
	for mutation: AttributeMutationResult in attributes.recompose_all():
		if not mutation.current_changed:
			continue
		if owner_asc != null:
			owner_asc.emit_attribute_changed(mutation, source_spec)
#endregion


#region Cues and events
func _play_cues(cue_tags: Array[StringName], spec: GameplayEffectSpec) -> void:
	if owner_asc == null:
		return
	for cue_tag: StringName in cue_tags:
		owner_asc.execute_cue(_cue_params_for(cue_tag, spec))


func _cue_params_for(cue_tag: StringName, spec: GameplayEffectSpec) -> GameplayCueParams:
	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = cue_tag
	params.instigator = spec.context.instigator if spec.context != null else null
	params.target = owner_asc.get_effect_target()
	params.context = spec.context
	return params


func _dispatch_events(spec: GameplayEffectSpec) -> void:
	if owner_asc == null:
		return
	owner_asc.dispatch_effect_events(spec)


func _notify_received(spec: GameplayEffectSpec) -> void:
	if owner_asc == null:
		return
	owner_asc.effect_received.emit(owner_asc.find_source_asc(spec), spec)


## Play the cues and fire the events of one periodic tick. Called by the
## scheduler, which owns when a tick is due.
func run_periodic_tick(active: ActiveGameplayEffect) -> void:
	var spec: GameplayEffectSpec = active.spec
	var evaluation: GameplayEffectEvaluationResult = _evaluate(spec, active.application_order)
	if not evaluation.is_ok():
		_report_refusal(evaluation)
		return

	for staged: AttributeBaseMutation in evaluation.base_mutations:
		attributes.commit_base_write(staged)

	recompose_and_emit(spec)
	_play_cues(spec.effect_def.periodic_cue_tags, spec)
	_dispatch_events(spec)
#endregion
