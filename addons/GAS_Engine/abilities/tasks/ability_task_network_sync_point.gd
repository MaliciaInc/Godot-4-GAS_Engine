## Wait for both sides to reach the same point in an ability.
##
## The task F5.5 needs and this phase can already shape. A predicted ability
## runs ahead on the machine that pressed the button and behind on the one that
## owns the game, and there are places in the middle where it must not run ahead
## any further - before it spends something, before it decides what it hit.
##
## Nothing here replicates anything. What it is is the point at which both
## sides agree they have arrived, and a way to say so; how the saying travels is
## F5.5's, and this is deliberately not guessing at it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskNetworkSyncPoint extends GameplayAbilityTask

## Which of the two is being waited for.
##
## ONLY_SERVER is a client waiting to be told to carry on. ONLY_CLIENT is the
## machine that owns the game waiting for the one that pressed the button. BOTH
## is a rendezvous: neither goes on until each has arrived.
enum Wait { ONLY_SERVER, ONLY_CLIENT, BOTH }

var waiting_for: AbilityTaskNetworkSyncPoint.Wait = Wait.BOTH

## Who has arrived so far.
var server_arrived: bool = false
var client_arrived: bool = false

## How long to wait before going on anyway, or zero to wait for ever.
##
## A sync point that can hang is a predicted ability that can hang, which is an
## ability holding its cost with nothing to release it. A game that would rather
## be wrong than stuck says so here.
var timeout: float = 0.0
var waited: float = 0.0
var timed_out: bool = false

## Which request this point is waiting on the answer to.
##
## The two `arrives` calls below were the whole of it when this task was
## written: something outside had to notice the answer and tell the task. That
## is a test's way of saying it and nobody's way of shipping it. Given a key,
## the task listens for the answer to the request the ability actually sent,
## and the machine that owns the game arriving is the confirm arriving.
##
## Null keeps the old shape exactly: a sync point nobody gave a key to is one
## the game drives itself, which is what every existing caller does.
var awaiting: GameplayPredictionKey = null

## Which run the authority confirmed, for a caller that wants to name it.
var confirmed_activation: GameplayNetActivationId = null

var _network: GameplayNetworkRuntime = null


static func create(
	ability: GameplayAbility,
	for_whom: AbilityTaskNetworkSyncPoint.Wait = Wait.BOTH,
	give_up_after: float = 0.0,
	awaiting_key: GameplayPredictionKey = null
) -> AbilityTaskNetworkSyncPoint:
	var task: AbilityTaskNetworkSyncPoint = AbilityTaskNetworkSyncPoint.new()
	task.owner_ability = ability
	task.waiting_for = for_whom
	task.timeout = give_up_after
	task.awaiting = awaiting_key
	return task


## Listens only when it was given something to listen for.
func _on_start() -> void:
	if awaiting == null or not awaiting.is_valid():
		return
	_network = _runtime()
	if _network != null:
		_network.activation_answered.connect(_on_answered)


func _on_finish() -> void:
	if _network != null and _network.activation_answered.is_connected(_on_answered):
		_network.activation_answered.disconnect(_on_answered)
	_network = null


func _runtime() -> GameplayNetworkRuntime:
	if owner_ability == null or owner_ability.owner_asc == null:
		return null
	return owner_ability.owner_asc.network


## The answer to the request this point is waiting on.
##
## A refusal is not a late arrival. An ability whose request was refused is
## not going to be confirmed afterwards, and a sync point that kept waiting
## would hold the ability open for its whole timeout and then let it carry on
## as though nothing had been refused.
func _on_answered(
	key: GameplayPredictionKey, activation: GameplayNetActivationId, accepted: bool
) -> void:
	if awaiting == null or not awaiting.same_as(key):
		return
	if not accepted:
		cancel(GameplayAbilityTask.CancelReason.ABILITY_ABORTED)
		return
	confirmed_activation = activation
	server_arrives()


## Say that the machine that owns the game has arrived.
func server_arrives() -> void:
	server_arrived = true
	_check()


## Say that the machine that pressed the button has.
func client_arrives() -> void:
	client_arrived = true
	_check()


func advance_time(delta: float) -> void:
	if is_finished():
		return
	waited += delta
	if timeout > 0.0 and waited >= timeout:
		timed_out = true
		succeed()


func _check() -> void:
	if is_finished():
		return
	match waiting_for:
		Wait.ONLY_SERVER:
			if server_arrived:
				succeed()
		Wait.ONLY_CLIENT:
			if client_arrived:
				succeed()
		_:
			if server_arrived and client_arrived:
				succeed()
