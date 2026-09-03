## Issues and resolves GameplayEffectHandle identities, and answers
## GameplayEffectQuery lookups over a runtime's active effects.
##
## Split out of GameplayEffectRuntime the same way GameplayLiveMagnitudeRegistry
## and GameplayEffectComponentRuntime are: a focused collaborator, composed
## into the parent rather than folded inside it. Owns no active-effect
## registry of its own - `find`/`count` are asked against the array the
## runtime already keeps.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectHandleRegistry extends RefCounted

var owner_asc: AbilitySystemComponent = null

## Needed only for remove_active_effects()/remove_active_effect_by_handle() -
## a query answers what matches on its own, but removing an effect is the
## runtime's own operation (tags, contributions, notifications), never
## duplicated here.
var runtime: GameplayEffectRuntime = null

var _by_id: Dictionary[int, ActiveGameplayEffect] = {}
var _next_id: int = 1


func new_handle() -> GameplayEffectHandle:
	var handle: GameplayEffectHandle = GameplayEffectHandle.new()
	handle.owner_instance_id = owner_asc.get_instance_id() if owner_asc != null else 0
	handle.id = _next_id
	_next_id += 1
	return handle


func register(active: ActiveGameplayEffect) -> void:
	if active != null and active.handle != null:
		_by_id[active.handle.id] = active


func forget(active: ActiveGameplayEffect) -> void:
	if active != null and active.handle != null:
		_by_id.erase(active.handle.id)


## Never resolves a handle from another ASC, even one that happens to share
## the same numeric id - owner_instance_id is checked first.
func resolve(handle: GameplayEffectHandle) -> ActiveGameplayEffect:
	if handle == null or not handle.is_valid() or owner_asc == null:
		return null
	if handle.owner_instance_id != owner_asc.get_instance_id():
		return null
	return _by_id.get(handle.id)


func find(query: GameplayEffectQuery) -> Array[ActiveGameplayEffect]:
	var matched: Array[ActiveGameplayEffect] = []
	for active: ActiveGameplayEffect in runtime.live_active_effects():
		if query == null or query.matches(active, owner_asc):
			matched.append(active)
	return matched


func find_handles(query: GameplayEffectQuery) -> Array[GameplayEffectHandle]:
	var found: Array[GameplayEffectHandle] = []
	for active: ActiveGameplayEffect in find(query):
		found.append(active.handle)
	return found


func count(query: GameplayEffectQuery) -> int:
	return find(query).size()


## Snapshots matching effects first, then removes - so removing while
## iterating the live array cannot skip an effect the removal itself shifts.
func remove_matching(query: GameplayEffectQuery) -> int:
	var matched: Array[ActiveGameplayEffect] = find(query)
	for active: ActiveGameplayEffect in matched:
		runtime.remove(active)
	return matched.size()


func remove_by_handle(handle: GameplayEffectHandle) -> bool:
	var active: ActiveGameplayEffect = resolve(handle)
	if active == null:
		return false
	runtime.remove(active)
	return true


func duration_remaining(handle: GameplayEffectHandle) -> float:
	var active: ActiveGameplayEffect = resolve(handle)
	if active == null:
		return 0.0
	var policy: GameplayEffect.DurationPolicy = active.get_effect_def().policy
	if policy == GameplayEffect.DurationPolicy.INFINITE:
		return INF
	if policy == GameplayEffect.DurationPolicy.DURATION:
		return active.time_remaining
	return 0.0


func turns_remaining(handle: GameplayEffectHandle) -> int:
	var active: ActiveGameplayEffect = resolve(handle)
	if active == null or active.spec == null:
		return 0
	if active.get_effect_def().policy != GameplayEffect.DurationPolicy.TURN_BASED:
		return 0
	return active.spec.remaining_turns
