## One thing a client did before it was allowed to, and how to undo it.
##
## Prediction is a client spending mana, starting a cooldown and playing a spark
## on the strength of a guess. Being told "no" is the easy half. The hard half
## is that by the time the answer arrives, more has been done on top of the
## guess, and taking the first thing back without the rest leaves a character
## holding a cooldown for an ability that never fired.
##
## So each thing is written down with the key it was done under, and taking it
## back is a method on the thing rather than a case in whoever is undoing it.
## The list is short and closed on purpose: everything here can be undone with
## what the operation itself remembers, and anything that cannot is not
## something to predict. A periodic tick, an arbitrary execution calculation and
## a server-only side effect are all in that second group, and this addon says
## so rather than pretending otherwise.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayPredictionOperation extends RefCounted

## What was done ahead of the answer.
##
## COST: what activating charged. Distinct from ATTRIBUTE_DELTA because they
##     are authored differently and read differently in a log, even though
##     taking either back is the same subtraction.
## COOLDOWN: the cooldown effect the client applied to itself.
## ATTRIBUTE_DELTA: a change to an attribute the ability made directly.
## CUE: something that was played.
enum Kind { COST, COOLDOWN, ATTRIBUTE_DELTA, CUE }

var kind: GameplayPredictionOperation.Kind = Kind.ATTRIBUTE_DELTA
var key: GameplayPredictionKey = null

## For COST and ATTRIBUTE_DELTA: which attribute, and the signed change that
## was made to its base. Signed, so undoing is one subtraction rather than two
## rules about which direction a cost goes in.
var attribute: StringName = &""
var applied_delta: float = 0.0

## For COOLDOWN: the effect the client applied to itself, to be taken off again.
var effect_handle: GameplayEffectHandle = null

## For CUE: what was played, and the handle if it was a persistent one.
var cue_tag: StringName = &""
var cue_handle: GameplayCueHandle = null

## Whether the authority has since agreed. An accepted operation is no longer a
## guess and must never be reversed - the state it produced is the state
## everybody has.
var accepted: bool = false


static func cost(
	under: GameplayPredictionKey, attribute_name: StringName, charged: float
) -> GameplayPredictionOperation:
	return _of(Kind.COST, under, attribute_name, -charged)


static func attribute_delta(
	under: GameplayPredictionKey, attribute_name: StringName, delta: float
) -> GameplayPredictionOperation:
	return _of(Kind.ATTRIBUTE_DELTA, under, attribute_name, delta)


static func cooldown(
	under: GameplayPredictionKey, handle: GameplayEffectHandle
) -> GameplayPredictionOperation:
	var made: GameplayPredictionOperation = _of(Kind.COOLDOWN, under, &"", 0.0)
	made.effect_handle = handle
	return made


static func cue(
	under: GameplayPredictionKey, tag: StringName, handle: GameplayCueHandle = null
) -> GameplayPredictionOperation:
	var made: GameplayPredictionOperation = _of(Kind.CUE, under, &"", 0.0)
	made.cue_tag = tag
	made.cue_handle = handle
	return made


static func _of(
	of_kind: GameplayPredictionOperation.Kind,
	under: GameplayPredictionKey,
	attribute_name: StringName,
	delta: float
) -> GameplayPredictionOperation:
	var made: GameplayPredictionOperation = GameplayPredictionOperation.new()
	made.kind = of_kind
	made.key = under
	made.attribute = attribute_name
	made.applied_delta = delta
	return made


## Put back what this did, and say whether anything was put back.
##
## False is an ordinary answer rather than a failure: a one-shot cue that has
## already played cannot be unplayed, and an effect that ended on its own is
## already gone. What matters is that the reversal was attempted and that
## nothing else is left standing on it.
func reverse(asc: AbilitySystemComponent) -> bool:
	if accepted or asc == null:
		return false
	match kind:
		Kind.COST, Kind.ATTRIBUTE_DELTA:
			return _take_back_the_change(asc)
		Kind.COOLDOWN:
			return _take_off_the_effect(asc)
		_:
			return _stop_the_cue(asc)


func _take_back_the_change(asc: AbilitySystemComponent) -> bool:
	if attribute == &"" or is_zero_approx(applied_delta):
		return false
	asc.set_attribute_base(attribute, asc.get_attribute_base(attribute) - applied_delta)
	return true


func _take_off_the_effect(asc: AbilitySystemComponent) -> bool:
	if effect_handle == null:
		return false
	var applied: ActiveGameplayEffect = asc.get_active_effect(effect_handle)
	if applied == null:
		return false
	asc.effects.remove(applied)
	return true


## A persistent cue can be stopped. A one-shot cannot: it has already been seen.
##
## Which is the reason a game predicts the impact spark and not the death
## animation - the first is worth being wrong about for a frame, and the second
## is a player watching something that did not happen.
func _stop_the_cue(asc: AbilitySystemComponent) -> bool:
	if cue_handle == null:
		return false
	asc.deactivate_persistent_cue(cue_handle, GameplayCueParams.for_target(cue_tag, null, null, 0.0))
	return true
