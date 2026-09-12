## What is active on one character, arranged so the two questions asked most
## often do not read the whole list.
##
## Both questions were linear in the number of active effects, and both are
## asked constantly: "which stack does this application join" on every
## application, and "which effects care that this tag moved" on every tag
## change. A character with a thousand effects on it paid a thousand
## comparisons for each, almost all of them against effects that could not
## possibly have been the answer.
##
## One index rather than one per question, and maintained in one place. The
## phase document puts a map on the stacking runtime and another on the
## inhibition runtime, each with the same six maintenance points written out
## twice - and two maintenance lists for one list of effects is how one of them
## comes to miss the purge path. What is here is fed by the five statements that
## can change `GameplayEffectRuntime._active` and by nothing else.
##
## It changes no answer. Both lookups are a smaller set to walk, in the same
## order the full list would have produced, and a debug build can be asked to
## check that against the scan it replaces.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectActiveIndex extends RefCounted

## What separates the parts of a bucket key. A character is never in it, so two
## different keys can never spell the same string.
const KEY_SEPARATOR: String = "|"

## Every active effect that could be the stack this application joins, by the
## identity that decides it: which definition, which stacking rule, and - when
## the rule aggregates by source - whose.
## The bucket arrays are untyped: GDScript refuses a typed collection inside a
## typed collection, so what the phase document writes as
## `Dictionary[String, Array[ActiveGameplayEffect]]` does not parse. Every read
## below assigns into a typed local, which is the conversion the engine checks.
var _by_stack_key: Dictionary[String, Array] = {}

## Every active effect whose requirements name a tag, by that tag.
var _by_requirement_tag: Dictionary[StringName, Array] = {}

## The few whose requirements name no tag at all: a query that is not empty and
## mentions nothing, which nothing can index and which is small enough to walk.
var _unindexed_requirements: Array[ActiveGameplayEffect] = []

## The ones that make their owner immune to something.
##
## Every application asked every active effect whether it granted immunity, and
## almost none of them do - a thousand effects on a character meant a thousand
## questions per application, of which at most a handful could answer yes.
var _immunities: Array[ActiveGameplayEffect] = []

## Which effects were indexed under what, so dropping one takes it out of every
## bucket it is in without asking the effect what it used to be. An effect whose
## definition or source changed after it was indexed would otherwise be looked
## for under a key it is no longer filed at, and stay in the index forever.
var _filed_stack_key: Dictionary[ActiveGameplayEffect, String] = {}
var _filed_requirement_tags: Dictionary[ActiveGameplayEffect, Array] = {}

#region What it cost
## How many candidates the last stack search compared, and how many effects the
## last tag change reevaluated.
##
## Counted always rather than under a debug flag: they are two integer
## increments on paths that do real work either way, and a counter that only
## exists in one kind of build is a counter no test in the other kind can check.
var stack_candidates_examined: int = 0
var inhibition_effects_reevaluated: int = 0

## And how many the last application asked about immunity.
var immunities_examined: int = 0


func forget_counters() -> void:
	stack_candidates_examined = 0
	inhibition_effects_reevaluated = 0
	immunities_examined = 0
#endregion


#region Keeping it
## File one active effect under everything it belongs to.
##
## Called once, when the effect is published. An effect already filed is refiled
## rather than filed twice, because "at most once per bucket" is the invariant
## that makes a bucket a set of candidates rather than a multiset of them.
func add(active: ActiveGameplayEffect) -> void:
	if active == null:
		return
	drop(active)

	var key: String = stack_key_of(active.get_effect_def(), active.spec.source_asc)
	_push(_by_stack_key, key, active)
	_filed_stack_key[active] = key

	if active.get_effect_def().get_immunity_query() != null:
		_immunities.append(active)

	var filed: Array[StringName] = GameplayEffectRequirementDependencies.of(
		active.get_effect_def()
	)
	if not GameplayEffectRequirementDependencies.has_requirements(active.get_effect_def()):
		# Neither query, so no tag change can make it transition. Filed nowhere
		# on purpose: this is most of what is on a character, and it is the
		# whole of what this index removes from a tag change.
		_filed_requirement_tags[active] = []
		return

	if filed.is_empty():
		_unindexed_requirements.append(active)
		_filed_requirement_tags[active] = []
		return

	for tag: StringName in filed:
		_push(_by_requirement_tag, tag, active)
	_filed_requirement_tags[active] = filed


## Take one out of every bucket it is in.
##
## By what it was filed under rather than by what it says now: an effect whose
## definition or source was swapped since is looked for under the key it was
## actually put at, which is the only way removal can be complete.
func drop(active: ActiveGameplayEffect) -> void:
	if active == null:
		return
	if _filed_stack_key.has(active):
		_pull(_by_stack_key, _filed_stack_key[active], active)
		_filed_stack_key.erase(active)
	if _filed_requirement_tags.has(active):
		for tag: Variant in _filed_requirement_tags[active]:
			_pull(_by_requirement_tag, tag, active)
		_filed_requirement_tags.erase(active)
	_unindexed_requirements.erase(active)
	_immunities.erase(active)


## File one again, after whatever it is filed under has changed.
##
## A stack replacement swaps the spec, and with it the source that decides an
## AggregateBySource key. Refiling is `drop` then `add`, which is what `add`
## already does - this exists so a caller says what it means.
func refresh(active: ActiveGameplayEffect) -> void:
	add(active)


func clear() -> void:
	_by_stack_key.clear()
	_by_requirement_tag.clear()
	_unindexed_requirements.clear()
	_immunities.clear()
	_filed_stack_key.clear()
	_filed_requirement_tags.clear()
#endregion


#region Asking it
## The identity that decides which stack an application joins.
##
## Definition, rule, and - only when the rule says so - source. An effect that
## does not stack gets a key nothing else shares, so it is filed and dropped by
## the same statements as everything else rather than being a special case at
## every call site.
static func stack_key_of(
	effect: GameplayEffect, source_asc: AbilitySystemComponent
) -> String:
	if effect == null:
		return ""
	var key: String = str(effect.get_instance_id()) + KEY_SEPARATOR + str(effect.stacking_type)
	if effect.stacking_type == GameplayEffect.StackingType.AGGREGATE_BY_SOURCE:
		key += KEY_SEPARATOR + (str(source_asc.get_instance_id()) if source_asc != null else "")
	return key


## Everything that could be the stack this spec joins, in application order.
##
## The bucket is appended to as effects are published and never reordered, so
## what comes back is the order the full list would have handed over.
func stack_candidates(spec: GameplayEffectSpec) -> Array[ActiveGameplayEffect]:
	var found: Array[ActiveGameplayEffect] = []
	if spec == null or spec.effect_def == null:
		return found
	var key: String = stack_key_of(spec.effect_def, spec.source_asc)
	if _by_stack_key.has(key):
		found.assign(_by_stack_key[key])
	# In application order, which is the order the full list is in: a bucket is
	# appended to as effects are published, but an extraction and a restoration
	# put one back at the end of its bucket and in the middle of the list.
	found.sort_custom(_by_application_order)
	stack_candidates_examined += found.size()
	return found


static func _by_application_order(
	left: ActiveGameplayEffect, right: ActiveGameplayEffect
) -> bool:
	return left.application_order < right.application_order


## Everything a change to this tag could make transition.
##
## The tag itself and every ancestor of it, because holding a descendant
## satisfies an ancestor and never the other way round - so a query about
## `State` hears about `State.Stunned` arriving, and a query about
## `State.Stunned` does not hear about a bare `State`.
##
## Each effect once, however many of its ancestors it is filed under.
func requirement_dependents(tag: StringName) -> Array[ActiveGameplayEffect]:
	var found: Array[ActiveGameplayEffect] = []
	found.append_array(_unindexed_requirements)
	for named: StringName in GameplayTagRuntime.ancestors_of(tag):
		if not _by_requirement_tag.has(named):
			continue
		var bucket: Array[ActiveGameplayEffect] = []
		bucket.assign(_by_requirement_tag[named])
		for active: ActiveGameplayEffect in bucket:
			if not found.has(active):
				found.append(active)
	inhibition_effects_reevaluated += found.size()
	return found


## Everything on this character that grants immunity to anything.
##
## In application order, which is the order the full list is in and therefore
## the order the first match was found in: an application refused by two
## immunities is refused by the older one, and a test that asked which would
## get a different answer from a bucket that had been appended to.
func immunities() -> Array[ActiveGameplayEffect]:
	var found: Array[ActiveGameplayEffect] = []
	found.assign(_immunities)
	found.sort_custom(_by_application_order)
	immunities_examined += found.size()
	return found


## How many effects are filed at all, for a test asking whether removal was
## complete.
func filed_count() -> int:
	return _filed_stack_key.size()
#endregion


#region Buckets
## Put one effect in a bucket, making the bucket if it is the first.
##
## The key is a Variant because the two maps are keyed differently - a stack key
## is a String and a requirement is a StringName - and Godot will not let a
## typed collection hold one, so the buckets are untyped arrays inside typed
## dictionaries. One pair of helpers rather than two: the arithmetic of a bucket
## is the same arithmetic whatever the key is, and the second copy is the one
## that stops matching.
static func _push(into: Dictionary, key: Variant, active: ActiveGameplayEffect) -> void:
	if not into.has(key):
		into[key] = []
	# Named rather than reached through twice. The dictionaries are
	# untyped because a typed one cannot hold a bucket of mixed keys, so
	# `into[key]` is a Variant - and an Array is a reference, so appending
	# to the local appends to the one in the dictionary.
	var bucket: Array = into[key]
	bucket.append(active)


## Take one out, and take the bucket away when it empties.
##
## Emptied rather than left: a map that kept a key per definition ever applied
## would grow with the character's history rather than with its state.
static func _pull(from: Dictionary, key: Variant, active: ActiveGameplayEffect) -> void:
	if not from.has(key):
		return
	var bucket: Array = from[key]
	bucket.erase(active)
	if bucket.is_empty():
		from.erase(key)
#endregion
