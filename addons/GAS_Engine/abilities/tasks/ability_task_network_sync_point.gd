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


static func create(
	ability: GameplayAbility,
	for_whom: AbilityTaskNetworkSyncPoint.Wait = Wait.BOTH,
	give_up_after: float = 0.0
) -> AbilityTaskNetworkSyncPoint:
	var task: AbilityTaskNetworkSyncPoint = AbilityTaskNetworkSyncPoint.new()
	task.owner_ability = ability
	task.waiting_for = for_whom
	task.timeout = give_up_after
	return task


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
