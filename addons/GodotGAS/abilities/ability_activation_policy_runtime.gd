## Everything ActivationPolicy needs beyond MANUAL: ON_GRANTED's one attempt
## at grant time, and PASSIVE's continuous reevaluation - starting an idle
## spec when its requirements allow, cancelling a running one when they stop.
##
## Split out of AbilityRuntime the same way AbilityInstancingRuntime/
## AbilityTagSemanticsRuntime are: request_passive_reevaluation()/
## reevaluate_passives()/active_requirements_error() are thin wrappers there,
## the logic lives here.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name AbilityActivationPolicyRuntime extends RefCounted

## A cap on reevaluation passes, not on how many passives exist - a passive
## whose own activation-owned tag falsifies its own required query would
## otherwise oscillate forever within one reevaluation. Same shape as
## GameplayEffectInhibitionRuntime.MAX_REQUIREMENT_REEVALUATION_PASSES.
const MAX_PASSIVE_REEVALUATION_PASSES: int = 64

var ability_runtime: AbilityRuntime = null

## Set by AbilityRuntime.abort_all() around its own teardown loop: a passive
## just aborted for ASC_CLEANUP must not restart itself before the ASC that
## owns it finishes tearing down.
var suspended: bool = false

var _reevaluating: bool = false
var _dirty: bool = false

## Every spec try_activate() was already called on this reevaluate() cycle.
## A passive whose _activate_ability() completes synchronously ends within
## that very call, going idle again before the next pass - without this, an
## eligible-but-instantly-finishing passive would restart on every remaining
## pass of the same cycle instead of once per external trigger.
var _attempted_this_cycle: Array[GameplayAbilitySpec] = []


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


## "Intentar activar una vez; si falla, permanece concedido; no reintentar
## automáticamente por tags" - unlike PASSIVE, a failed ON_GRANTED attempt is
## never retried by reevaluate(), which only ever looks at PASSIVE specs.
func _activate_once(spec: GameplayAbilitySpec) -> void:
	if ability_runtime.activation_error(spec) != AbilityRuntime.ActivationError.NONE:
		return
	var instance: GameplayAbility = ability_runtime.instancing.instance_for_activation(spec)
	if instance != null:
		instance.try_activate()
#endregion


#region Passive reevaluation
## Something that could change a passive's eligibility happened: tags,
## attributes, another ability's active_count, or a grant/remove.
func request_reevaluation() -> void:
	if suspended:
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
		instance.try_activate()
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
