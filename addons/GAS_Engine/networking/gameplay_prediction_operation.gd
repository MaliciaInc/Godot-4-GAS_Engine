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
## something to predict. Four things are named as being in that second group
## rather than left to be discovered one bug at a time:
##
## - a periodic tick, because how many of them happened is a clock the two
##   machines do not share;
## - an arbitrary execution's calculation, because what it did is whatever it
##   decided and nothing wrote down the inverse;
## - a custom cost with no prediction kind, which is what `Kind.NONE` is for -
##   a cost that says out loud that it cannot be taken back;
## - a server-side effect nothing here can observe, since a client cannot undo
##   what it was never able to see.
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
## What a client may guess at, and undo when it guessed wrong.
##
## NONE is last so the four that existed keep the numbers they had. It is not a
## fifth thing to predict: it is a cost saying it is not predictable at all,
## which is the default for anything the journal cannot reverse from what the
## operation itself remembers - an inventory, a durability, a quest step.
## TAG: a tag this machine held ahead of the answer, with the counts either
##     side of the change - a tag is a reference count, and putting it back
##     means putting the number back rather than removing one.
## ANIMATION: a playback started on a surface this activation claimed. Only
##     reversible while it is still the claim the surface records: another
##     ability that has since taken the surface is playing something this
##     guess has no business stopping.
##
## TAG and ANIMATION are last for the same reason NONE is: the four that
## existed keep the numbers they had.
enum Kind { COST, COOLDOWN, ATTRIBUTE_DELTA, CUE, NONE, TAG, ANIMATION }

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

## For TAG: which tag, and the count either side of the change.
##
## Both counts rather than a delta. The count is what says whether this is
## still the machine's own guess to take back: a reading from the authority
## that arrived after it moves the number, and a reversal on top of that
## would be this machine overwriting the authority with an arithmetic it did
## on its own.
var changed_tag: StringName = &""
var old_count: int = 0
var new_count: int = 0

## For ANIMATION: the claim taken on the surface when the playback started.
##
## The ownership token, and the only thing that makes an animation
## reversible at all: it says which activation of which instance started
## this, and it can be asked - late, after the node may be gone - whether
## that is still what the surface records.
var ownership: GameplayAnimationOwnership = null

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


## A tag held ahead of the answer, with the counts either side of it.
static func tag(
	under: GameplayPredictionKey, tag_name: StringName, was: int, now: int
) -> GameplayPredictionOperation:
	var made: GameplayPredictionOperation = _of(Kind.TAG, under, &"", 0.0)
	made.changed_tag = tag_name
	made.old_count = was
	made.new_count = now
	return made


## A playback started on a surface this activation claimed.
static func animation(
	under: GameplayPredictionKey, claim: GameplayAnimationOwnership
) -> GameplayPredictionOperation:
	var made: GameplayPredictionOperation = _of(Kind.ANIMATION, under, &"", 0.0)
	made.ownership = claim
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
##
## What guards against undoing the authority rather than the guess: `accepted`,
## for everything - an operation the authority has agreed to is no longer this
## machine's - and then, for the two kinds that can say more, the thing itself.
## A tag says the count is still the one the guess left; a playback says the
## surface still records this activation. A cost and an attribute delta have no
## such answer here and are guarded only by `accepted`: an authoritative reading
## that moved the same attribute between the guess and the refusal is undone
## with it, and correcting that needs the next reading rather than this method.
func reverse(asc: AbilitySystemComponent) -> bool:
	if accepted or asc == null:
		return false
	match kind:
		Kind.COST, Kind.ATTRIBUTE_DELTA:
			return _take_back_the_change(asc)
		Kind.COOLDOWN:
			return _take_off_the_effect(asc)
		Kind.TAG:
			return _put_the_tag_back(asc)
		Kind.ANIMATION:
			return _stop_the_animation()
		Kind.CUE:
			return _stop_the_cue(asc)
		_:
			# NONE, and nothing else: the enum is closed. Nothing was guessed,
			# so there is nothing to take back, and saying so here rather than
			# falling into somebody else's arm is why each kind is named.
			return true


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


## Put a tag's count back, while it is still the count this guess produced.
##
## The ownership check, in the only form a tag has one. A tag is a reference
## count and the authority replicates it as a number: a reading that arrived
## since the guess has already written what the authority believes, and this
## machine putting its own arithmetic back on top would undo it. So the count
## has to still be the one this guess left, and if it is not, there is nothing
## here that is still ours to take back.
##
## By adding and removing rather than by writing the number, because the count
## is a reference count and everything watching it - a passive ability's
## requirement, an immunity - is listening to the signals those raise.
func _put_the_tag_back(asc: AbilitySystemComponent) -> bool:
	if changed_tag == &"" or old_count == new_count:
		return false
	var held: int = asc.tags.count_exact(changed_tag)
	if held != new_count:
		return false
	while held < old_count:
		asc.add_tag(changed_tag)
		held += 1
	while held > old_count:
		asc.remove_tag(changed_tag)
		held -= 1
	return true


## Stop a playback, while this activation is still the one that owns it.
##
## The receipt answers that on its own, after the fact and without the node:
## another ability that has since taken the surface is playing something this
## guess has no business stopping, and a mixer that has been freed is not one
## anybody is still watching. Both are ordinary, and both are false.
func _stop_the_animation() -> bool:
	if ownership == null or not ownership.still_holds():
		return false
	var surface: GameplayAnimationSurface = GameplayAnimationSurface.of(ownership.mixer())
	if surface == null:
		return false
	surface.halt()
	ownership.release()
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
