## One granted ability: activation rules, cost/cooldown, and the logic a
## subclass overrides. Event payload is typed, unlike upstream's Variant.
##
## @meta_addon: GAS_Engine
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
class_name GameplayAbility extends Node


## PER_ACTOR: one instance for the grant's lifetime, second activation
## refused while running. PER_EXECUTION: one instance per activation.
##
## NON_INSTANCED declares that an activation keeps no state of its own: whatever
## it needs comes from the definition or from the context it is handed. Godot
## has no class default object to run it on, and sharing one mutable Node
## between concurrent activations would give them each other's state - which is
## the bug the policy exists to make impossible. So it runs on a fresh Node that
## is never adopted as the spec's instance and never outlives the activation,
## and what the policy buys is the contract: nothing may be read back off it
## afterwards, because there is nothing to read.
enum InstancingPolicy {
	PER_ACTOR,
	PER_EXECUTION,
	NON_INSTANCED,
}

## MANUAL: input/explicit call. ON_GRANTED: tries once, never auto-retries.
## ON_GAMEPLAY_EVENT: gameplay_event_triggers decide. PASSIVE: continuously
## reevaluated - see AbilityActivationPolicyRuntime.
enum ActivationPolicy {
	MANUAL,
	ON_GRANTED,
	ON_GAMEPLAY_EVENT,
	PASSIVE,
	## Runs while the input is held: the press starts it, the release ends
	## it. Distinct from MANUAL with a wait-for-release task inside,
	## because the ability declares the shape rather than implementing it,
	## and a runtime that knows the shape can end it when the input is lost
	## for reasons the ability never sees - a window losing focus, a
	## controller unplugged.
	WHILE_INPUT_ACTIVE,
}


## Where this ability is allowed to run, once a game has a network.
##
## LOCAL_ONLY: it runs here and is nobody else's business. The default, and
##     deliberately: it is what every ability written before this existed
##     already did, and a default that changed behaviour under an existing
##     project would be this field breaking games to describe them.
## LOCAL_PREDICTED: the owning client runs it at once and asks; the authority
##     answers, and a refusal is reversed rather than argued with.
## SERVER_INITIATED: the client asks and waits. Nothing happens on the asking
##     machine until the authority says it did.
## SERVER_ONLY: the authority runs it and nobody may ask - a scripted effect,
##     an environmental trigger, anything a client requesting would be a
##     client fabricating.
##
## Frozen at grant time like the policies above it: what a grant may do is
## decided when it is granted, not by editing the scene it came from while a
## match is running.
enum NetExecutionPolicy {
	LOCAL_ONLY,
	LOCAL_PREDICTED,
	SERVER_INITIATED,
	SERVER_ONLY,
}

signal ability_ended(was_cancelled: bool)

@export_category("Ability Rules")
@export var ability_name: String = ""

## Frozen at grant time, same as instancing_policy.
@export var activation_policy: GameplayAbility.ActivationPolicy = ActivationPolicy.MANUAL

## Frozen at grant time, same as activation_policy.
@export var net_execution_policy: GameplayAbility.NetExecutionPolicy = (
	NetExecutionPolicy.LOCAL_ONLY
)

## The name of the field above, for the two readers that have to look it up
## rather than read it: the snapshot's drift watch, and the network runtime
## reading a policy off a packed scene it has no instance of.
const NET_EXECUTION_POLICY_FIELD: StringName = &"net_execution_policy"

## Identity, not activation gating - effective tags are these plus dynamic_tags.
@export var ability_tags: Array[StringName] = []

## Read once at grant time into the frozen definition - editing after does nothing.
@export var instancing_policy: GameplayAbility.InstancingPolicy = InstancingPolicy.PER_ACTOR

## Whether returning from `_activate_ability()` ends the ability.
##
## True is what this engine has always done and stays the default, because
## turning it off under an existing project would leave every ability running
## forever. An ability that means to outlive its own activation function - one
## that waits on a task, or on an event, and ends itself later - sets it false
## and calls `end_ability()` when it is actually done.
@export var auto_end_on_activate_return: bool = true

## Whether activating this again while it is already running is allowed.
##
## False refuses, which is what a cooldown-less ability wants: pressing twice
## does not stack. True ends the activation in flight and starts a new one, so
## the second press replaces the first rather than being ignored.
@export var retrigger_while_active: bool = false

@export var ability_level: float = 1.0

## Empty/null imposes no requirement.
@export var activation_required_query: GameplayTagQuery = null
@export var activation_blocked_query: GameplayTagQuery = null

## Granted once on active_count 0->1, retired once on 1->0 - never per PER_EXECUTION instance.
@export var activation_owned_tags: Array[StringName] = []

## On successful activation, other granted specs matching this are cancelled - not this one unless allow_self_cancel.
@export var cancel_abilities_query: GameplayTagQuery = null
@export var allow_self_cancel: bool = false

## While active_count > 0, blocks a matching new activation (BLOCKED_BY_ACTIVE_ABILITY, not BLOCKED_TAG).
@export var block_abilities_query: GameplayTagQuery = null

## Gates accepts_target() - see apply_effect_to_targets(), the sole enforcement route.
## Tag gates on whoever caused this activation, read from the event's
## instigator snapshot rather than from the world.
##
## Only consulted when an activation arrives carrying a GameplayEventData
## with tags on it. An event with no instigator does not invent one, so a
## non-empty required query refuses rather than passing by default.
@export var source_required_query: GameplayTagQuery = null
@export var source_blocked_query: GameplayTagQuery = null
@export var target_required_query: GameplayTagQuery = null
@export var target_blocked_query: GameplayTagQuery = null

@export_category("Ability Mechanics")
## Every priced entry this charges. Empty means free; resolved once at commit.
@export var costs: Array[GameplayAbilityCost] = []

## A cost authored as a gameplay effect, for a project that prices things
## that way already.
##
## Accepted only when the commit contract can prove it is an instant, silent,
## reversible charge - which is the same bar the resolver's own output has to
## clear. An effect with executions, cues or a duration is refused at grant
## rather than at the first press, because a commit that cannot be undone
## breaks the one promise this engine makes about paying for things.
@export var cost_effect: GameplayEffect = null

## Costs this engine cannot price: ammunition, an item, a stack on a tag.
##
## Each hands back an object that knows both what it took and how to put it
## back, so they are part of the same all-or-nothing commit as everything
## else rather than something a game does around it and hopes.
@export var custom_costs: Array[GameplayAbilityCustomCost] = []
@export var cooldown_effect: GameplayEffect
@export var shared_cooldown_effects: Array[GameplayEffect] = []
@export var shared_cooldown_tags: Array[StringName] = []

@export_category("Ability Triggers")
## Only consulted for ON_GAMEPLAY_EVENT - any one matching trigger wakes this.
@export var gameplay_event_triggers: Array[GameplayAbilityEventTrigger] = []

@export_category("Input Routing")
## The input slot this ability answers, or -1 when unbound.
@export var input_id: int = -1

## The InputMap action this ability answers, for a project that routes input
## by name. Empty means it does not answer one.
@export var input_action: StringName = &""

## The context of the activation currently running. Null when idle.
var current_context: GameplayEffectContext = null

var owner_asc: AbilitySystemComponent = null

## Null until granted; once set, read level/input through the accessors below.
var current_spec: GameplayAbilitySpec = null

var is_active: bool = false

## Which activation of this instance is running, counting from one.
##
## An instance is reused - a PER_ACTOR ability activated twice is the same
## Node both times - so "this ability" is not enough to say whose a piece of
## work is. An animation started by the activation before this one is not this
## one's to wait on, and a retrigger is exactly that case. Zero while idle.
var activation_id: int = 0

## Whether this activation has already paid. One activation charges once.
var _committed: bool = false

var _reported_drift: bool = false

## What _run_activation() resolved to - read after try_activate() awaits `ability_ended`.
var _last_activation_succeeded: bool = false


## Why this activation happened, set by the runtime as it starts.
var _activation_context: GameplayAbilityActivationContext = null


#region What an ability is told
## The event that activated this, or null when a call did.
##
## Handed over rather than rebuilt: everything the event knew - the tag that
## fired it, the magnitude it carried, who it was aimed at - is on it, and an
## ability that reconstructed any of that from the world would be reading a
## world that has moved on since.
## @composer
func get_activation_event() -> GameplayEventData:
	return _activation_context.gameplay_event if _activation_context != null else null



## Called once, after this ability has been granted and wired to its owner.
##
## Empty here: it is a hook, and an ability that needs nothing does nothing.
func on_granted() -> void:
	pass


## Called once, as the grant is being taken away, before anything is severed.
func on_removed() -> void:
	pass


## Called when the body this ability happens to has been exchanged.
##
## Announced rather than polled, so an ability holding a reference to the old
## avatar is told rather than finding out by acting on a corpse.
func on_avatar_changed(_old_avatar: Node, _new_avatar: Node) -> void:
	pass


## Whether this ability may be cancelled from outside right now.
##
## True by default, because refusing to be cancelled is the exception and an
## ability that never says otherwise should behave the way every ability
## behaved before there was a way to say it. An uninterruptible finisher
## overrides it; a teardown ignores it, because a component going away is not a
## request.
## Whether this ability wants the event that matched one of its triggers.
##
## The trigger says the event is for this ability; this says whether it wants
## it right now. Answering false is a refusal without a reason, so anything
## the caller should be told about belongs in a tag gate instead.
func should_respond_to_event(_event: GameplayEventData) -> bool:
	return true


## An answer set at runtime, when something set one. -1 means nobody did and
## the virtual below decides.
##
## An override rather than a field replacing the virtual: an ability that
## computes whether it may be interrupted - not while the blade is down, not
## during the last half second - is answering a question a boolean cannot,
## and replacing it with one would silently break every ability that did.
var _cancelability_override: int = -1


## Say whether this may be cancelled, overruling what the ability computes.
## @composer
func set_can_be_cancelled(value: bool) -> void:
	_cancelability_override = 1 if value else 0


## What everything asks. The override when there is one, the ability's own
## answer when there is not.
func is_cancellable() -> bool:
	if _cancelability_override >= 0:
		return _cancelability_override == 1
	return can_be_cancelled()


func can_be_cancelled() -> bool:
	return true
#endregion


#region Spec accessors
## current_spec once granted; the exported default for an uncommitted probe.
## @composer
func get_ability_level() -> float:
	return current_spec.level if current_spec != null else ability_level


## @composer
func get_input_id() -> int:
	return current_spec.input_id if current_spec != null else input_id


## Null when this instance was never granted through the grant pipeline.
## @composer
func get_ability_handle() -> GameplayAbilityHandle:
	return current_spec.handle if current_spec != null else null
#endregion


#region Execution
## Compat: blocks until this finishes, unlike AbilityRuntime.try_activate().
## @composer
func try_activate(context: GameplayEffectContext = null) -> bool:
	if is_active or owner_asc == null:
		return false
	if not owner_asc.can_activate_ability(self, true):
		return false
	_begin_runtime_activation(context)
	if is_active:
		await ability_ended
	return _last_activation_succeeded


## Registers active state only. The lifecycle runtime must announce activation
## before user code is allowed to finish/cancel/remove it.
func _prepare_runtime_activation(context: GameplayEffectContext) -> void:
	is_active = true
	if current_spec != null:
		current_spec.active_count += 1
		if current_spec.active_count == 1:
			_set_activation_owned_tags(true)
		owner_asc.ability_runtime.request_passive_reevaluation()
	current_context = context
	_cancel_conflicting_abilities()


## Execute only while this activation is still alive. A listener of
## ability_activated is allowed to cancel/remove it before this runs.
func _execute_runtime_activation() -> void:
	if not is_active:
		return
	_run_activation()


## Compatibility wrapper for old direct callers.
func _begin_runtime_activation(context: GameplayEffectContext) -> void:
	_prepare_runtime_activation(context)
	_execute_runtime_activation()


## Whether returning from `_activate_ability()` ends this ability.
##
## Read off the frozen definition once granted, and off the export before that.
## The grant is what every other decision is made from, and an ability whose own
## field said one thing while its definition said another would end at a
## different moment depending on which one was asked.
func _ends_when_activation_returns() -> bool:
	if current_spec != null and current_spec.definition != null:
		return current_spec.definition.auto_end_on_activate_return
	return auto_end_on_activate_return


func _run_activation() -> void:
	# `await` hands a coroutine's value back untyped - a channelled ability
	# crashed on resume with an Object where a bool belonged.
	var outcome: Variant = await _activate_ability()
	var success: bool = outcome is bool and outcome
	_last_activation_succeeded = success

	# Only close if the subclass hasn't already, so `ability_ended` fires once -
	# and only if this ability ends when its activation function returns. One
	# that waits on something and finishes later says so, and closing it here
	# would end it before the thing it is waiting for ever happens.
	if is_active and _ends_when_activation_returns():
		end_ability(not success)
		current_context = null


## Pay cost and start cooldowns as one transaction, called from
## `_activate_ability` once committed - all-or-nothing, no cues/events by
## contract, so a rollback leaves nothing observable.
## What this ability's cost would be, and whether it can be paid right now.
##
## Asked without charging, so a caller can offer an ability greyed out rather
## than let somebody press it and be refused. Resolving is not free, and what it
## produces is carried out rather than recomputed: two resolutions of one cost
## are two opinions about what an ability costs.
## @composer
func check_cost() -> AbilityCommitPreflight:
	var preflight: AbilityCommitPreflight = AbilityCommitPreflight.new()
	if owner_asc == null or current_spec == null:
		preflight.status = AbilityCommitPreflight.Status.INVALID_COST
		return preflight

	var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(
		current_spec.definition.costs, owner_asc, current_spec.level
	)
	preflight.resolved_cost = resolved

	if (
		resolved.status != GameplayResolvedCost.Status.OK
		and resolved.status != GameplayResolvedCost.Status.INSUFFICIENT_RESOURCES
	):
		preflight.status = AbilityCommitPreflight.Status.INVALID_COST
		return preflight

	# Self-check against the resolver's own output - a violation means it is
	# broken, and paying a charge that cannot be reversed is unrecoverable.
	if not AbilityCommitContract.is_reversible_charge(resolved.absolute_effect, 1.0):
		preflight.status = AbilityCommitPreflight.Status.INVALID_COST
		return preflight
	# The authored effect answers the same question, and answers it before
	# anything is charged: an effect with executions, cues or a duration
	# cannot be taken back, and a commit that cannot be taken back is not
	# the thing this engine promised.
	var authored: GameplayEffect = current_spec.definition.cost_effect
	if authored != null and not AbilityCommitContract.is_reversible_charge(
		authored, current_spec.level
	):
		preflight.status = AbilityCommitPreflight.Status.INVALID_COST
		return preflight
	# And every custom cost is asked, without being taken.
	for custom: GameplayAbilityCustomCost in current_spec.definition.custom_costs:
		if custom == null:
			preflight.status = AbilityCommitPreflight.Status.INVALID_COST
			return preflight
		var asked: GameplayAbilityCustomCostCheck = custom.check(
			owner_asc, current_spec, current_spec.level
		)
		if asked == null or not asked.can_pay:
			preflight.refused_custom_cost = asked
			preflight.status = AbilityCommitPreflight.Status.INSUFFICIENT_RESOURCES
			return preflight

	if resolved.status == GameplayResolvedCost.Status.INSUFFICIENT_RESOURCES:
		preflight.status = AbilityCommitPreflight.Status.INSUFFICIENT_RESOURCES
	return preflight


## Which cooldowns this ability would start, and whether one is already running.
##
## Both halves, because either alone lets an ability through that should not
## be: a cooldown that cannot legally be applied is a definition mistake, and
## one that is already running means somebody else got there first.
## @composer
func check_cooldown() -> AbilityCommitPreflight:
	var preflight: AbilityCommitPreflight = AbilityCommitPreflight.new()
	if owner_asc == null or current_spec == null:
		preflight.status = AbilityCommitPreflight.Status.INVALID_COOLDOWN
		return preflight

	preflight.cooldowns = AbilityCommitContract.unique_cooldowns(
		current_spec.definition.cooldown_effect,
		current_spec.definition.shared_cooldown_effects
	)
	for cooldown: GameplayEffect in preflight.cooldowns:
		if not AbilityCommitContract.is_legal_cooldown(cooldown):
			preflight.status = AbilityCommitPreflight.Status.INVALID_COOLDOWN
			return preflight

	var running: Array[StringName] = AbilityCooldownRuntime.get_cooldown_tags(current_spec)
	if owner_asc.tags.has_any(running):
		preflight.status = AbilityCommitPreflight.Status.ON_COOLDOWN
	return preflight


## Start every cooldown the preflight found, or undo what was started.
## @composer
func apply_cooldown(
	preflight: AbilityCommitPreflight, result: AbilityCommitResult
) -> bool:
	for cooldown: GameplayEffect in preflight.cooldowns:
		var started: ActiveGameplayEffect = owner_asc.apply_gameplay_effect(
			cooldown, owner_asc, current_spec.level
		)
		if started == null:
			return _fail_commit(
				result, AbilityCommitResult.Status.COOLDOWN_APPLICATION_FAILED
			)
		result.applied_cooldowns.append(started)
		result.transaction.applied_cooldowns.append(started)
	return true


## Take the charge the preflight resolved, or undo the cooldowns already started.
## @composer
func apply_cost(preflight: AbilityCommitPreflight, result: AbilityCommitResult) -> bool:
	# Everything is prepared before anything is taken, so a refusal at any
	# point below has nothing to put back but what this function itself already
	# took - and the transaction is holding all of that.
	if not _prepare_custom_costs(result):
		return false

	var charge: GameplayEffect = preflight.resolved_cost.absolute_effect
	if charge != null:
		var charged: ActiveGameplayEffect = owner_asc.apply_gameplay_effect(
			charge, owner_asc, 1.0
		)
		if charged == null:
			return _fail_commit(result, AbilityCommitResult.Status.COST_APPLICATION_FAILED)
		result.applied_cost = charged
		result.transaction.charged(charge, 1.0)

	var authored: GameplayEffect = current_spec.definition.cost_effect
	if authored != null:
		var applied: ActiveGameplayEffect = owner_asc.apply_gameplay_effect(
			authored, owner_asc, current_spec.level
		)
		if applied == null:
			return _fail_commit(result, AbilityCommitResult.Status.COST_APPLICATION_FAILED)
		result.transaction.charged(authored, current_spec.level)

	if not result.transaction.commit_custom_costs():
		return _fail_commit(result, AbilityCommitResult.Status.COST_APPLICATION_FAILED)
	return true


## Ask every custom cost to work out what it would take, before any of them
## takes it. One that cannot be prepared refuses while nothing has been
## touched, which is the cheapest possible failure.
func _prepare_custom_costs(result: AbilityCommitResult) -> bool:
	for custom: GameplayAbilityCustomCost in current_spec.definition.custom_costs:
		var prepared: GameplayAbilityPreparedCustomCost = custom.prepare(
			owner_asc, current_spec, current_spec.level
		)
		if prepared == null:
			return _fail_commit(result, AbilityCommitResult.Status.COST_APPLICATION_FAILED)
		result.transaction.prepared(prepared)
	return true


## Undo everything this commit took and say why it stopped.
##
## One place, so no failure path can forget a half of it - which is exactly how
## a commit ends up having charged for something it did not do.
func _fail_commit(
	result: AbilityCommitResult, why: AbilityCommitResult.Status
) -> bool:
	_roll_back(result)
	result.status = why
	return false


## The whole price, or none of it.
##
## The only transactional coordinator: check, check again, pay, and undo what
## was paid if the second half cannot be finished. Both checks run twice on
## purpose - once to decide, and once immediately before the first write,
## because starting a cooldown raises signals and a listener is entitled to move
## the resources this was about to take.
## @composer
func commit_ability() -> AbilityCommitResult:
	var result: AbilityCommitResult = AbilityCommitResult.new()
	if owner_asc == null:
		result.status = AbilityCommitResult.Status.OWNER_MISSING
		return result
	if _committed:
		result.status = AbilityCommitResult.Status.ALREADY_COMMITTED
		return result

	# The snapshot froze this ability's authoring, so it is what can tell when
	# this instance stopped agreeing with it. Said once: it is a wiring mistake.
	if not _reported_drift:
		_reported_drift = GameplayAbilityDefinitionSnapshot.report_drift(
			self, current_spec.definition)

	var cost: AbilityCommitPreflight = check_cost()
	result.resolved_cost = cost.resolved_cost
	if not cost.is_ok():
		result.status = cost.as_commit_status()
		return result

	var cooldown: AbilityCommitPreflight = check_cooldown()
	if not cooldown.is_ok():
		result.status = cooldown.as_commit_status()
		return result

	if not apply_cooldown(cooldown, result):
		return result

	# Asked again, not trusted from a moment ago: every cooldown that just
	# started raised signals, and a listener is allowed to have spent the
	# resources this is about to take.
	var again: AbilityCommitPreflight = check_cost()
	if not again.is_ok():
		_roll_back(result)
		result.status = AbilityCommitResult.Status.RESOURCES_CHANGED_DURING_COMMIT
		return result

	if not apply_cost(again, result):
		return result

	_committed = true
	result.status = AbilityCommitResult.Status.SUCCESS
	_announce_commit(result)
	return result


## Say what a commit did, whichever way it went.
##
## Every path out of `commit_ability()` passes through here or through a refusal
## above it, so a listener hears about the commits that failed as well - which
## are the ones somebody is debugging.
func _announce_commit(result: AbilityCommitResult) -> void:
	if owner_asc == null or current_spec == null:
		return
	owner_asc.ability_committed.emit(current_spec.handle, result)


## Undo cooldowns a failed commit already started; emptied too, so the result reports nothing applied.
## Put back everything this commit took, in the order that makes putting it
## back mean anything.
##
## Delegated to the transaction, which is the thing that knows what was taken:
## a rollback written here would have to be kept in step with every route a
## cost can arrive by, and there are three of those now.
func _roll_back(result: AbilityCommitResult) -> void:
	result.transaction.undo(owner_asc)
	result.applied_cooldowns.clear()
	result.applied_cost = null


## Override this. The default succeeds immediately.
func _activate_ability() -> bool:
	return true


## Interrupt mid-cast.
## @composer
func abort_ability(
	reason: GameplayAbilityTask.CancelReason = GameplayAbilityTask.CancelReason.ABILITY_ABORTED
) -> void:
	if is_active:
		end_ability(true, reason)


## Stays granted: ending is not un-granting. `is_active` clears first, since
## cancelling a task can resume a coroutine that would otherwise double-emit.
## Wait until this ability is done, and return at once if it already is.
##
## `try_activate()` returns when activation BEGINS, so an ability that refuses -
## or has nothing to do - has already ended by the time a caller sees the
## result, and awaiting `ability_ended` then waits for what will not fire
## again. The counterpart of `GameplayAbilityTask.completed()`.
func completed() -> void:
	if not is_active:
		return
	await ability_ended


## @composer
func end_ability(
	was_cancelled: bool = false,
	reason: GameplayAbilityTask.CancelReason = GameplayAbilityTask.CancelReason.ABILITY_ENDED
) -> void:
	if not is_active:
		return
	is_active = false
	# Before anything else that ends: a provider still previewing is a preview on
	# screen for an ability that is over, and whoever is waiting on it is waiting
	# for an answer nobody will give.
	_stop_aiming()
	# And every cue this activation left running. An aura on a character
	# whose stance ended is the same class of thing as a preview on screen
	# for an ability that is over.
	_stop_persistent_cues()
	if current_spec != null:
		current_spec.active_count = maxi(current_spec.active_count - 1, 0)
		if current_spec.active_count == 0:
			_set_activation_owned_tags(false)
	if owner_asc != null:
		owner_asc.cancel_ability_tasks(self, reason)
		owner_asc.ability_runtime.request_passive_reevaluation()
		if current_spec != null:
			owner_asc.ability_runtime_ended.emit(current_spec.handle, self, was_cancelled, reason)
	# The one place a commit is forgotten - two owners for one transition otherwise.
	_committed = false
	ability_ended.emit(was_cancelled)


## See AbilityTagSemanticsRuntime.set_activation_owned_tags.
func _set_activation_owned_tags(grant: bool) -> void:
	if owner_asc == null:
		return
	owner_asc.ability_runtime.tag_semantics.set_activation_owned_tags(current_spec, grant)


## See AbilityTagSemanticsRuntime.cancel_conflicting_abilities.
func _cancel_conflicting_abilities() -> void:
	if owner_asc == null:
		return
	owner_asc.ability_runtime.tag_semantics.cancel_conflicting_abilities(current_spec)
#endregion


#region Helpers
## Play a cue on the owning entity.
## @composer
func execute_cue(tag: StringName) -> void:
	if owner_asc == null:
		return
	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = tag
	params.instigator = owner_asc.get_effect_target()
	params.target = owner_asc.get_effect_target()
	owner_asc.execute_cue(params)


## Start a cue that runs until this ability stops it, or until the ability
## ends.
##
## The difference from `execute_cue` is the whole of it: a one-shot cue is
## over when it is over, and this one is not - a channel's beam, an aura
## while a stance is held. Which means it can be left behind, and the reason
## an ability's persistent cues are its own ledger is that it must not be.
##
## The handle comes back, so an ability that wants to stop one early can.
## Ignoring it is the ordinary case: everything still running is stopped when
## the ability ends, however it ends.
## @composer
func activate_persistent_cue(
	tag: StringName, params: GameplayCueParams = null
) -> GameplayCueHandle:
	if owner_asc == null:
		return GameplayCueHandle.new()
	var told: GameplayCueParams = params if params != null else GameplayCueParams.new()
	told.cue_tag = tag
	if told.instigator == null:
		told.instigator = owner_asc.get_effect_target()
	if told.target == null:
		told.target = owner_asc.get_effect_target()
	var handle: GameplayCueHandle = owner_asc.activate_persistent_cue(told)
	if handle.is_valid():
		_persistent_cues.append(handle)
		_persistent_cue_params.append(told)
	return handle


## Stop one persistent cue this ability started. False for a handle it did
## not start, which is the case a shared handle makes real: one activation
## must never end another's cue.
## @composer
func deactivate_persistent_cue(handle: GameplayCueHandle) -> bool:
	if handle == null or owner_asc == null:
		return false
	for index: int in _persistent_cues.size():
		if _persistent_cues[index].id != handle.id:
			continue
		owner_asc.deactivate_persistent_cue(handle, _persistent_cue_params[index])
		_persistent_cues.remove_at(index)
		_persistent_cue_params.remove_at(index)
		return true
	return false


## End every persistent cue this activation started, and nothing else.
##
## Called from the one place an ability stops, so a normal end, a cancel, an
## abort and a grant being taken away all go through it. Paired by index with
## the params each cue was started with, because a removal cue is played with
## what the activation knew rather than with whatever the caller happens to
## be holding.
func _stop_persistent_cues() -> void:
	if owner_asc != null:
		for index: int in _persistent_cues.size():
			owner_asc.deactivate_persistent_cue(
				_persistent_cues[index], _persistent_cue_params[index]
			)
	_persistent_cues.clear()
	_persistent_cue_params.clear()


## Reads the frozen snapshot's target_required/blocked_query, immune to edits.
## @composer
func accepts_target(target_asc: AbilitySystemComponent) -> bool:
	if target_asc == null or current_spec == null or current_spec.definition == null:
		return false
	var required: GameplayTagQuery = current_spec.definition.target_required_query
	if required != null and not required.is_empty() and not required.matches_runtime(target_asc.tags):
		return false
	var blocked: GameplayTagQuery = current_spec.definition.target_blocked_query
	if blocked != null and not blocked.is_empty() and blocked.matches_runtime(target_asc.tags):
		return false
	return true


## Each target gets its own spec copy - sharing one across an AoE let target
## A's evaluation change what target B received.
## @composer
func apply_effect_to_targets(
	effect_res: GameplayEffect, target_data: GameplayAbilityTargetData
) -> GameplayTargetApplicationResult:
	var result: GameplayTargetApplicationResult = GameplayTargetApplicationResult.new()
	if effect_res == null or target_data == null or owner_asc == null:
		return result

	# Instigator/causer are the persistent avatar - `self` would dangle once
	# the ability ends.
	var avatar: Node = owner_asc.get_effect_target()
	var context: GameplayEffectContext = GameplayEffectContext.new(avatar, avatar)
	context.target_data = target_data
	context.ability_handle = get_ability_handle()
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(effect_res, context, get_ability_level())
	var reached: Array[int] = []
	var unreachable: Array[int] = []
	# Only what the aim actually holds. An aim that is a place with nobody
	# standing on it reaches nobody, and the engine does not go looking for
	# somebody nearby on its own: an implicit overlap here would be an area
	# effect nobody authored, with a radius nobody chose.
	for target: Node in target_data.get_target_nodes():
		if target == null:
			continue
		result.attempted_targets += 1

		var target_asc: AbilitySystemComponent = find_asc_on(target)
		if target_asc == null:
			if not unreachable.has(target.get_instance_id()):
				unreachable.append(target.get_instance_id())
				result.missing_asc_targets.append(target)
			continue

		# Two colliders on one actor are one target - twice would double an
		# AoE for anything with two hitboxes.
		if reached.has(target_asc.get_instance_id()):
			continue
		reached.append(target_asc.get_instance_id())

		# Sole enforcement route for target_required/blocked_query.
		if not accepts_target(target_asc):
			result.rejected_targets.append(target_asc)
			continue

		# What THIS target was hit by, and nothing about anybody else. Handing
		# every victim the whole aim tells each of them about the others - a "did
		# this hit my head" check answering yes because it hit somebody else's.
		var applied: GameplayEffectApplicationResult = (
			owner_asc.apply_effect_spec_to_target_result(
				spec, target_asc, target_data.copied(target)
			)
		)
		result.applications.append(applied)
		if not applied.is_ok():
			result.rejected_targets.append(target_asc)
			continue
		result.applied_targets.append(target_asc)
		result.applied_effects.append(applied.active_effect)
	if result.attempted_targets == 0:
		result.refusal = GameplayTargetApplicationResult.Refusal.NO_ACTOR_TARGETS
	return result


## The ability system a node belongs to - no algorithm of its own, one search.
## @composer
## @composer_name: Find The Ability System On
static func find_asc_on(node: Node) -> AbilitySystemComponent:
	return AbilitySystemLocator.find_for_node(node)


## Convenience wrapper - the implementation lives on AbilityRuntime, keyed by spec.
## @composer
func get_cooldown_tags() -> Array[StringName]:
	return AbilityRuntime.get_cooldown_tags(current_spec)


## Everything a UI needs, read fresh. Live-instance wrapper; AbilityRuntime answers by handle.
## @composer
func get_cooldown_state() -> AbilityCooldownState:
	if owner_asc == null or current_spec == null:
		return AbilityCooldownState.new()
	return owner_asc.get_ability_cooldown_state(current_spec.handle)
#endregion


#region Input Routing
## The bound input was pressed.
func _input_pressed(asc: AbilitySystemComponent) -> void:
	if is_active:
		_active_input_pressed(asc)
		return
	if owner_asc != null:
		owner_asc.ability_runtime.try_activate(get_ability_handle())


## The bound input was released.
func _input_released(asc: AbilitySystemComponent) -> void:
	if not is_active:
		return
	# The policy decides first, because WHILE_INPUT_ACTIVE means the release
	# is what ends the ability - and an ability that also wrote a hook for it
	# would then be asked to handle an ability that is already over.
	if (
		current_spec != null
		and current_spec.definition != null
		and current_spec.definition.activation_policy
			== GameplayAbility.ActivationPolicy.WHILE_INPUT_ACTIVE
	):
		end_ability(false)
		return
	_active_input_released(asc)


## Pressed while running. Override for "press again to cancel/detonate".
func _active_input_pressed(_asc: AbilitySystemComponent) -> void:
	pass


## Released while running. Override for "hold to charge, release to fire".
func _active_input_released(_asc: AbilitySystemComponent) -> void:
	pass
#endregion


#region Task factories
## Null when there is no ASC - a task nobody owns could never be cancelled.
func _own(task: GameplayAbilityTask) -> GameplayAbilityTask:
	if task == null or owner_asc == null:
		return null
	return owner_asc.register_ability_task(task)


## @composer
func wait_delay(seconds: float) -> AbilityTaskWaitDelay:
	return _own(AbilityTaskWaitDelay.create(self, seconds)) as AbilityTaskWaitDelay


## `-1` means this ability's own bound slot. Resolved in the body, not a
## default parameter value: that would freeze `input_id` at parse time.
## @composer
func wait_input_pressed(input_slot: int = -1) -> AbilityTaskWaitInput:
	return _wait_input(input_slot, AbilityTaskWaitInput.Transition.PRESSED)


## @composer
func wait_input_released(input_slot: int = -1) -> AbilityTaskWaitInput:
	return _wait_input(input_slot, AbilityTaskWaitInput.Transition.RELEASED)


func _wait_input(
	input_slot: int, transition: AbilityTaskWaitInput.Transition
) -> AbilityTaskWaitInput:
	var slot: int = get_input_id() if input_slot == -1 else input_slot
	return _own(AbilityTaskWaitInput.create(self, slot, transition)) as AbilityTaskWaitInput


## @composer
func wait_gameplay_event(tag: StringName) -> AbilityTaskWaitGameplayEvent:
	var task: GameplayAbilityTask = _own(AbilityTaskWaitGameplayEvent.create(self, tag))
	return task as AbilityTaskWaitGameplayEvent


## The same wait, kept open.
##
## Every match is announced through `event_received` and the task stays until
## the ability ends or somebody cancels it - which is what "while I channel,
## every time I am hit" needs, and what a loop around the one-shot above was
## standing in for.
## @composer
func wait_gameplay_events(
	tag: StringName,
	only_match_exact: bool = false,
	from_asc: AbilitySystemComponent = null
) -> AbilityTaskWaitGameplayEvent:
	return _own(
		AbilityTaskWaitGameplayEvent.create(self, tag, false, only_match_exact, from_asc)
	) as AbilityTaskWaitGameplayEvent


## @composer
func wait_target_data() -> AbilityTaskWaitTargetData:
	return _own(AbilityTaskWaitTargetData.create(self)) as AbilityTaskWaitTargetData


## Answer this ability's own request for targets.
## @composer
## The providers this ability is aiming with, so it can call them off.
##
## A list rather than one: an ability that asks for a point and then a direction
## is aiming twice, and the second would silently replace the first if there
## were only room for one.
var _aiming: Array[GameplayTargetProvider] = []

## Persistent cues this activation started and has not stopped.
##
## Kept by the activation rather than by the component, because whose cue it
## is is the question that matters: one activation ending must not take away
## another's, and a component-wide list could not tell them apart.
##
## Two arrays paired by index rather than a dictionary, because a handle is a
## RefCounted and a dictionary keyed by one is keyed by identity - a caller
## holding an equal handle from the wire would not find its own entry.
var _persistent_cues: Array[GameplayCueHandle] = []
var _persistent_cue_params: Array[GameplayCueParams] = []


func submit_target_data(data: GameplayAbilityTargetData) -> void:
	if owner_asc != null:
		owner_asc.submit_ability_target_data(self, data)


## Aim with `provider`, and hand over whatever it confirms.
##
## The join between a provider's life and an ability's. What a provider confirms
## is submitted the same way any other target data is, so a task already waiting
## on `wait_target_data()` hears it without knowing a provider was involved -
## and a game that aims some other way keeps working unchanged.
##
## The ability holds the provider until it ends, and then cancels it. A provider
## that outlived the ability that started it is the shape of bug this whole
## lifecycle is for: a preview left on screen, and something waiting on a
## confirm that is never coming.
## @composer
func aim_with(provider: GameplayTargetProvider) -> void:
	if provider == null or not is_active:
		return
	_aiming.append(provider)
	provider.confirmed.connect(submit_target_data)
	provider.begin(self)


## Call off every provider this ability started that is still going.
## Wait for something to enter an area the game already put in the world.
##
## The area is handed in because an engine that built one would be choosing a
## game's collision layers, shape and placement - three decisions it cannot
## make and should not guess at.
## @composer
func wait_overlap(
	area: Node, filter: GameplayTargetFilter = null
) -> AbilityTaskWaitOverlap:
	return _own(AbilityTaskWaitOverlap.create(self, area, filter)) as AbilityTaskWaitOverlap


## Wait until the avatar is moving the way it was told to.
##
## A zero direction means any direction and the speed alone decides; a real
## one asks for movement along it, which is how a dash waits for the dash
## rather than for any motion at all.
## @composer
func wait_velocity_change(
	direction: Vector3 = Vector3.ZERO, min_magnitude: float = 0.0
) -> AbilityTaskWaitVelocityChange:
	return _own(
		AbilityTaskWaitVelocityChange.create(self, direction, min_magnitude)
	) as AbilityTaskWaitVelocityChange


## Wait until this ability lands an effect on somebody else.
## @composer
func wait_effect_applied_to_target(
	query: GameplayEffectQuery = null
) -> AbilityTaskWaitEffectAppliedToTarget:
	return _own(
		AbilityTaskWaitEffectAppliedToTarget.create(self, query)
	) as AbilityTaskWaitEffectAppliedToTarget


## Declare that the ability is in a named stretch of itself.
##
## Ended by name from outside, which is the point: an animation, a listener or
## another ability can end a wind-up without holding the task that is the
## wind-up. Two states with different names run at once.
## @composer
func start_ability_state(state_name: StringName) -> AbilityTaskAbilityState:
	return _own(
		AbilityTaskAbilityState.create(self, state_name)
	) as AbilityTaskAbilityState


## End every state of this name. Answers how many there were.
## @composer
func end_ability_state(state_name: StringName) -> int:
	return end_task(state_name)


## Call off every state of this name. Answers how many there were.
## @composer
func cancel_ability_state(state_name: StringName) -> int:
	return cancel_task(state_name)


## Finish every task this ability owns by that name, successfully.
##
## Every one, not the first: three tasks called "channel" are the channel, and
## ending one of them would leave the ability half in a state it declared it
## had left.
## @composer
func end_task(instance_name: StringName) -> int:
	return _finish_named(instance_name, true)


## Call off every task this ability owns by that name.
## @composer
func cancel_task(instance_name: StringName) -> int:
	return _finish_named(instance_name, false)


func _finish_named(instance_name: StringName, successfully: bool) -> int:
	if instance_name == &"" or owner_asc == null:
		return 0
	var affected: int = 0
	for task: GameplayAbilityTask in owner_asc.ability_runtime.tasks.active_tasks():
		if task.owner_ability != self or task.instance_name != instance_name:
			continue
		affected += 1
		if successfully:
			task.succeed()
		else:
			task.cancel(GameplayAbilityTask.CancelReason.ABILITY_ABORTED)
	return affected


## The providers this ability is currently choosing with.
##
## A copy: the component walks these to route a generic confirm, and
## confirming one can end the ability, which clears the list it is walking.
func aiming_providers() -> Array[GameplayTargetProvider]:
	return _aiming.duplicate()


func _stop_aiming() -> void:
	for provider: GameplayTargetProvider in _aiming:
		provider.cancel()
	_aiming.clear()
#endregion
