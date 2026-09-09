## Everything ActivationPolicy needs beyond MANUAL: ON_GRANTED's one attempt
## at grant time, and PASSIVE's continuous reevaluation - starting an idle
## spec when its requirements allow, cancelling a running one when they stop.
##
## Split out of AbilityRuntime the same way AbilityInstancingRuntime/
## AbilityTagSemanticsRuntime are: request_passive_reevaluation()/
## reevaluate_passives()/active_requirements_error() are thin wrappers there,
## the logic lives here.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityActivationPolicyRuntime extends RefCounted

## A cap on reevaluation passes, not on how many passives exist - a passive
## whose own activation-owned tag falsifies its own required query would
## otherwise oscillate forever within one reevaluation. Same shape as
## GameplayEffectInhibitionRuntime.MAX_REQUIREMENT_REEVALUATION_PASSES.
const MAX_PASSIVE_REEVALUATION_PASSES: int = 64

var ability_runtime: AbilityRuntime = null

## How many teardowns are holding reevaluation off right now.
##
## AbilityRuntime.abort_all() holds one around its own loop: a passive just
## aborted must not restart itself before the ASC that owns it has finished
## tearing down.
##
## A depth, not a flag. Aborting fires `ability_ended` and
## `ability_runtime_ended`, which are public signals a game listens to - "the
## caster died, stop everything" is an ordinary handler - and a handler that
## reaches `abort_all` again lowered the flag on its way out while the outer
## teardown was still running. The nested call then asked for a reevaluation
## with nothing suspended, and the passive the ASC was in the middle of
## destroying started itself up again.
var _suspension_depth: int = 0


## Hold reevaluation off for the duration of a teardown.
func begin_suspension() -> void:
	_suspension_depth += 1


func end_suspension() -> void:
	_suspension_depth = maxi(_suspension_depth - 1, 0)


func is_suspended() -> bool:
	return _suspension_depth > 0

var _reevaluating: bool = false
var _dirty: bool = false

## Every spec try_activate() was already called on this reevaluate() cycle.
## A passive whose _activate_ability() completes synchronously ends within
## that very call, going idle again before the next pass - without this, an
## eligible-but-instantly-finishing passive would restart on every remaining
## pass of the same cycle instead of once per external trigger.
var _attempted_this_cycle: Array[GameplayAbilitySpec] = []


#region Tag triggers
## The component whose tag transitions this runtime is listening to.
##
## Held so the connections can be taken back. A runtime that connected and
## never disconnected would keep a torn-down component reachable through its
## own signal list.
var _listening_to: AbilitySystemComponent = null

## Specs a trigger has asked to start, waiting for the drain below.
##
## A queue rather than a direct call: an ability whose activation grants the
## tag that fired it is a loop somebody writes by accident, and a direct call
## would recurse until the stack gave out. This converges or stops counting.
var _woken: Array[GameplayAbilitySpec] = []
var _draining: bool = false


## Start listening for the transitions triggers are declared against.
func bind_to(asc: AbilitySystemComponent) -> void:
	if asc == null or _listening_to == asc:
		return
	unbind()
	_listening_to = asc
	asc.tag_added.connect(_on_tag_added)
	asc.tag_or_child_presence_changed.connect(_on_tag_presence_changed)


## Stop listening. Called from AbilityRuntime.dispose().
func unbind() -> void:
	if _listening_to == null or not is_instance_valid(_listening_to):
		_listening_to = null
		return
	if _listening_to.tag_added.is_connected(_on_tag_added):
		_listening_to.tag_added.disconnect(_on_tag_added)
	if _listening_to.tag_or_child_presence_changed.is_connected(_on_tag_presence_changed):
		_listening_to.tag_or_child_presence_changed.disconnect(_on_tag_presence_changed)
	_listening_to = null


## An acquisition edge. Only OWNED_TAG_ADDED triggers care, and losing the
## tag again never cancels what one of them started.
func _on_tag_added(tag: StringName) -> void:
	if is_suspended() or ability_runtime == null:
		return
	for spec: GameplayAbilitySpec in ability_runtime.specs():
		if _declares_trigger(spec, GameplayAbilityEventTrigger.Source.OWNED_TAG_ADDED, tag):
			_wake(spec)
	_drain()


## A level, in either direction. OWNED_TAG_PRESENT starts on the way up and
## cancels on the way down, because the tag is the condition the ability runs
## under rather than the thing that started it.
func _on_tag_presence_changed(tag: StringName, present: bool) -> void:
	if is_suspended() or ability_runtime == null:
		return
	for spec: GameplayAbilitySpec in ability_runtime.specs():
		if not _declares_trigger(
			spec, GameplayAbilityEventTrigger.Source.OWNED_TAG_PRESENT, tag
		):
			continue
		if present:
			_wake(spec)
		else:
			_end_by_requirement(spec)
	_drain()


## Whether this spec declares a trigger of `source` whose query covers `tag`.
##
## The query is matched against a single-element set, which is the same rule
## GameplayEventRuntime applies to an event's own tag - one hierarchy contract
## for both, rather than two that drift.
static func _declares_trigger(
	spec: GameplayAbilitySpec,
	source: GameplayAbilityEventTrigger.Source,
	tag: StringName
) -> bool:
	if spec == null or spec.definition == null:
		return false
	for trigger: GameplayAbilityEventTrigger in spec.definition.gameplay_event_triggers:
		if trigger == null or trigger.source != source or trigger.event_query == null:
			continue
		if trigger.event_query.matches_tags([tag] as Array[StringName]):
			return true
	return false


## Whether the owner currently satisfies any OWNED_TAG_PRESENT trigger.
static func _present_trigger_satisfied(
	spec: GameplayAbilitySpec, tags: GameplayTagRuntime
) -> bool:
	if spec == null or spec.definition == null or tags == null:
		return false
	for trigger: GameplayAbilityEventTrigger in spec.definition.gameplay_event_triggers:
		if (
			trigger == null
			or trigger.source != GameplayAbilityEventTrigger.Source.OWNED_TAG_PRESENT
			or trigger.event_query == null
		):
			continue
		if trigger.event_query.matches_runtime(tags):
			return true
	return false


func _wake(spec: GameplayAbilitySpec) -> void:
	if not _woken.has(spec):
		_woken.append(spec)


## Start everything a trigger woke, and everything those wake in turn, up to
## the pass limit. Beyond it the engine stops rather than recursing: an
## ability that grants its own trigger tag has asked for something nothing
## can give it.
func _drain() -> void:
	if _draining:
		return
	_draining = true
	var passes: int = 0
	while not _woken.is_empty() and passes < MAX_PASSIVE_REEVALUATION_PASSES:
		passes += 1
		var batch: Array[GameplayAbilitySpec] = _woken.duplicate()
		_woken.clear()
		for spec: GameplayAbilitySpec in batch:
			if ability_runtime != null and ability_runtime.get_spec(spec.handle) != null:
				ability_runtime.try_activate(spec.handle)
	if not _woken.is_empty():
		push_warning(
			"GAS_Engine: a tag trigger kept waking itself; stopped after "
			+ str(passes) + " passes."
		)
		_woken.clear()
	_draining = false


## End every activation of this spec because the condition it ran under is
## gone.
##
## Through the instance rather than through a public cancel: an ability that
## refuses cancellation is refusing a request, and this is not a request. The
## same route a passive takes when its required query stops matching.
func _end_by_requirement(spec: GameplayAbilitySpec) -> void:
	var instance: GameplayAbility = spec.per_actor_instance
	if instance != null and is_instance_valid(instance) and instance.is_active:
		instance.abort_ability(GameplayAbilityTask.CancelReason.CANCEL_TAG)
	for execution: GameplayAbility in spec.active_instances.duplicate():
		if is_instance_valid(execution) and execution.is_active:
			execution.abort_ability(GameplayAbilityTask.CancelReason.CANCEL_TAG)
#endregion


#region Grant-time activation
## Called once, right after a spec is registered and can be found by handle.
func on_spec_granted(spec: GameplayAbilitySpec) -> void:
	if spec == null or spec.definition == null:
		return
	match spec.definition.activation_policy:
		GameplayAbility.ActivationPolicy.ON_GRANTED:
			_activate_once(spec)
		GameplayAbility.ActivationPolicy.PASSIVE:
			request_reevaluation()

	# A level trigger has to look at the level it was granted into, not only
	# at the next transition: an ability declared "while burning" on a
	# character that is already burning would otherwise wait for it to stop
	# and start again.
	if _present_trigger_satisfied(spec, ability_runtime.tags):
		_wake(spec)
		_drain()


## "Intentar activar una vez; si falla, permanece concedido; no reintentar
## automáticamente por tags" - unlike PASSIVE, a failed ON_GRANTED attempt is
## never retried by reevaluate(), which only ever looks at PASSIVE specs.
## try_activate() itself already no-ops on a gate refusal.
func _activate_once(spec: GameplayAbilitySpec) -> void:
	ability_runtime.try_activate(spec.handle)
#endregion


#region Passive reevaluation
## Something that could change a passive's eligibility happened: tags,
## attributes, another ability's active_count, or a grant/remove.
func request_reevaluation() -> void:
	if is_suspended():
		return
	if _reevaluating:
		_dirty = true
		return
	reevaluate()


## Snapshot the granted specs, start the idle PASSIVE ones that now qualify,
## cancel the running ones that no longer do, repeat while dirty. The
## reentrancy flag alone is enough to converge: a passive's own activation
## can synchronously mark this dirty again (an activation-owned tag change,
## another ability's block_abilities_query), and that only extends the
## current pass loop rather than recursing into a nested one.
func reevaluate() -> void:
	if _reevaluating:
		_dirty = true
		return
	_reevaluating = true
	_attempted_this_cycle.clear()
	var passes: int = 0
	while passes < MAX_PASSIVE_REEVALUATION_PASSES:
		_dirty = false
		passes += 1
		_reevaluate_one_pass()
		if not _dirty:
			break
	_reevaluating = false


func _reevaluate_one_pass() -> void:
	for spec: GameplayAbilitySpec in ability_runtime.specs():
		if spec.definition == null or spec.definition.activation_policy != GameplayAbility.ActivationPolicy.PASSIVE:
			continue
		_reevaluate_one_spec(spec)


## PASSIVE + PER_EXECUTION is refused at grant time, so a passive's spec
## always has a per_actor_instance once committed.
func _reevaluate_one_spec(spec: GameplayAbilitySpec) -> void:
	var instance: GameplayAbility = spec.per_actor_instance
	if instance == null or not is_instance_valid(instance):
		return
	if instance.is_active:
		if active_requirements_error(spec) != AbilityRuntime.ActivationError.NONE:
			instance.abort_ability(GameplayAbilityTask.CancelReason.CANCEL_TAG)
		return
	if _attempted_this_cycle.has(spec):
		return
	if ability_runtime.activation_error(spec) == AbilityRuntime.ActivationError.NONE:
		_attempted_this_cycle.append(spec)
		ability_runtime.try_activate(spec.handle)
#endregion


#region Active-continuity gate
## What would cancel an already-running passive - never ALREADY_ACTIVE (it
## is), never cost/cooldown (continuity is not a purchase, only the
## required/blocked queries and block-by-active-ability are).
func active_requirements_error(spec: GameplayAbilitySpec) -> AbilityRuntime.ActivationError:
	if spec == null or spec.definition == null:
		return AbilityRuntime.ActivationError.INTERNAL_ERROR
	if spec.pending_remove:
		return AbilityRuntime.ActivationError.PENDING_REMOVAL
	if AbilityRuntime.query_matches_runtime(spec.definition.activation_blocked_query, ability_runtime.tags):
		return AbilityRuntime.ActivationError.BLOCKED_TAG
	var required: GameplayTagQuery = spec.definition.activation_required_query
	if required != null and not required.is_empty() and not required.matches_runtime(ability_runtime.tags):
		return AbilityRuntime.ActivationError.MISSING_TAG
	if ability_runtime.tag_semantics.blocked_by_active_ability(spec):
		return AbilityRuntime.ActivationError.BLOCKED_BY_ACTIVE_ABILITY
	return AbilityRuntime.ActivationError.NONE
#endregion
