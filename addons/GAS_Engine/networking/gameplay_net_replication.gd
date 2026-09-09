## Reading a component's state, working out what changed, and writing it back.
##
## Three jobs that belong together because they are three views of one shape:
## what a snapshot contains decides what a delta can say, and what a delta can
## say decides what applying one is able to do.
##
## The client does not re-simulate. What arrives is the authority's answer, and
## a client that ran the same effects again to arrive at its own would get a
## second answer that drifts from the first the moment a tick lands on a
## different frame. So attributes arrive as values, tags as counts, and effects
## as a reading - which definition, how many, how long left - for a game to show
## rather than to run. The authority is the one machine that simulates.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetReplication extends RefCounted

## How much of an entity's state a given peer is told.
##
## FULL: everything, to everybody. What a co-op game wants, where every player's
##     UI shows every other player's buffs.
## MIXED: the effects go to the owner alone; everyone else gets the attributes,
##     the tags and the cues. The competitive default - what a character is
##     doing is public, the twelve modifiers behind it are not, and it is also
##     most of the bandwidth.
## MINIMAL: nobody gets the effects, not even the owner. For entities whose
##     buffs are nobody's business at all - large numbers of them, mostly.
enum Mode { FULL, MIXED, MINIMAL }


## Everything about a component, filtered to what this recipient may be told.
static func snapshot_of(
	asc: AbilitySystemComponent,
	registry: GameplayNetRegistry,
	mode: GameplayNetReplication.Mode = Mode.FULL,
	for_owner: bool = true
) -> GameplayNetState:
	var state: GameplayNetState = GameplayNetState.snapshot()
	if asc == null:
		return state

	for name: StringName in asc.attributes.all_attribute_names():
		state.attributes[name] = asc.get_attribute_base(name)
	for tag: StringName in asc.tags.active_tags():
		state.tags[tag] = asc.tags.count_exact(tag)
	for spec: GameplayAbilitySpec in asc.get_ability_specs():
		var granted: GameplayNetDefinitionId = registry.register_definition(_scene_of(spec))
		if not granted.is_valid():
			continue
		state.abilities.append(granted.value)
		if for_owner and _tells_that_it_is_running(spec):
			state.running_abilities.append(granted.value)

	for active: ActiveGameplayEffect in asc.get_active_effects():
		for binding: GameplayCueBinding in active.get_effect_def().get_persistent_cue_bindings():
			# A local-only cue never reaches a wire. It plays where it was
			# decided and is nobody else's business - the crunch under your own
			# footsteps is not something to spend a packet on - and this is the
			# one place it could have leaked into somebody else's state.
			if binding.replication == GameplayCueBinding.Replication.LOCAL_ONLY:
				continue
			if not state.cues.has(binding.cue_tag):
				state.cues.append(binding.cue_tag)
		if _tells_about_effects(mode, for_owner):
			var reading: GameplayNetEffectState = _read(active, registry)
			if reading != null:
				state.effects.append(reading)
	return state


## Whether this grant's activations are anybody else's business.
##
## Asked of the frozen definition, and false unless it was authored to say
## otherwise. REPLICATE_YES is for the abilities whose middle matters - a
## channel a UI draws a bar for, a stance another player has to be able to
## see - and for everything else the start and the end are the whole story.
static func _tells_that_it_is_running(spec: GameplayAbilitySpec) -> bool:
	if spec == null or spec.definition == null or spec.active_count <= 0:
		return false
	return (
		spec.definition.replication_policy
		== GameplayAbility.ReplicationPolicy.REPLICATE_YES
	)


## Whether this recipient is told what is running, as opposed to what it did.
static func _tells_about_effects(mode: GameplayNetReplication.Mode, for_owner: bool) -> bool:
	match mode:
		Mode.FULL:
			return true
		Mode.MIXED:
			return for_owner
		_:
			return false


## What changed between two readings.
##
## Both directions, because a delta that only carried what appeared would leave
## a client holding every buff that ever landed on a character.
static func delta_between(
	before: GameplayNetState, after: GameplayNetState
) -> GameplayNetState:
	var change: GameplayNetState = GameplayNetState.delta()
	if before == null or after == null:
		return change

	for name: StringName in after.attributes:
		if not before.attributes.has(name) or not is_equal_approx(
			before.attributes[name], after.attributes[name]
		):
			change.attributes[name] = after.attributes[name]
	for tag: StringName in after.tags:
		if before.tags.get(tag, 0) != after.tags[tag]:
			change.tags[tag] = after.tags[tag]
	for tag: StringName in before.tags:
		if not after.tags.has(tag):
			change.removed_tags.append(tag)

	_diff_lists(before.abilities, after.abilities, change.abilities, change.revoked_abilities)
	_diff_lists(
		before.running_abilities,
		after.running_abilities,
		change.running_abilities,
		change.stopped_abilities
	)
	_diff_cues(before.cues, after.cues, change)
	_diff_effects(before, after, change)
	return change


## What appeared and what went away, for two lists of ids.
static func _diff_lists(
	before: Array[int], after: Array[int], appeared: Array[int], gone: Array[int]
) -> void:
	for one: int in after:
		if not before.has(one):
			appeared.append(one)
	for one: int in before:
		if not after.has(one):
			gone.append(one)


static func _diff_cues(
	before: Array[StringName], after: Array[StringName], change: GameplayNetState
) -> void:
	for tag: StringName in after:
		if not before.has(tag):
			change.cues.append(tag)
	for tag: StringName in before:
		if not after.has(tag):
			change.ended_cues.append(tag)


## An effect is news when it appeared or when any of its readings moved: one
## more stack, less time left, newly inhibited.
static func _diff_effects(
	before: GameplayNetState, after: GameplayNetState, change: GameplayNetState
) -> void:
	for one: GameplayNetEffectState in after.effects:
		if not one.same_as(before.effect(one.id)):
			change.effects.append(one.copied())
	for one: GameplayNetEffectState in before.effects:
		if after.effect(one.id) == null:
			change.ended_effects.append(one.id)


## Write what arrived onto a component.
##
## Attributes and tags only. An effect is applied by the authority and read
## here, never re-run: writing the modifiers again on top of attribute values
## that already have them in would count everything twice. What the effects in
## the state are for is a game's own display, and `GameplayNetState` is handed
## to it whole.
static func apply(state: GameplayNetState, asc: AbilitySystemComponent) -> bool:
	if state == null or asc == null:
		return false

	for name: StringName in state.attributes:
		asc.set_attribute_base(name, state.attributes[name])
	for tag: StringName in state.tags:
		_hold_exactly(asc, tag, state.tags[tag])
	for tag: StringName in state.removed_tags:
		_hold_exactly(asc, tag, 0)
	if not state.is_delta():
		_drop_tags_not_in(state, asc)
	return true


## Bring a tag's count to what the authority says it is.
##
## By adding and removing rather than by writing the number, because the count
## is a reference count and everything else that reads it - a passive ability's
## requirement, an immunity - is watching the signals those emit.
static func _hold_exactly(asc: AbilitySystemComponent, tag: StringName, wanted: int) -> void:
	var held: int = asc.tags.count_exact(tag)
	while held < wanted:
		asc.add_tag(tag)
		held += 1
	while held > wanted:
		asc.remove_tag(tag)
		held -= 1


## A snapshot is the whole truth, so a tag it does not mention is a tag that is
## not there - which a delta could never say, and is why the two are told apart.
static func _drop_tags_not_in(state: GameplayNetState, asc: AbilitySystemComponent) -> void:
	for tag: StringName in asc.tags.active_tags():
		if not state.tags.has(tag):
			_hold_exactly(asc, tag, 0)


static func _scene_of(spec: GameplayAbilitySpec) -> Resource:
	if spec == null or spec.definition == null:
		return null
	return spec.definition.ability_scene


## One reading of a running effect, or null when its definition cannot be named
## to another machine - an effect built in memory has nowhere to live and
## nothing to call it.
static func _read(
	active: ActiveGameplayEffect, registry: GameplayNetRegistry
) -> GameplayNetEffectState:
	var named: GameplayNetDefinitionId = registry.register_definition(active.get_effect_def())
	if not named.is_valid():
		return null
	var reading: GameplayNetEffectState = GameplayNetEffectState.of(
		registry.net_effect_id(active.handle), named.value
	)
	reading.stack_count = active.stack_count
	reading.time_remaining = active.time_remaining
	reading.remaining_turns = active.spec.remaining_turns
	reading.inhibited = active.inhibited
	return reading
