## An authority with one entity registered on it, which every networking suite
## needs before it can say anything.
##
## Four lines each time, in eight suites, and the fourth is the one people get
## wrong: a component the runtime was never told about is an entity every
## message about it is refused for, and the refusal reads like the thing the
## test was checking.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name NetBench extends RefCounted

const Fixture = preload("res://test/fixtures/asc_fixture.gd")

## The peer that owns the entity, and one that is only watching.
const OWNING_PEER: int = 2
const WATCHING_PEER: int = 3

var runtime: GameplayNetworkRuntime = null
var fixture: ASCFixture = null
var entity: GameplayNetEntityId = null

## Where a mirror fixture goes, once `client()` has been asked for one.
var _parent: Node = null

## The client's own copy of the character, once `client()` has built one.
##
## A component keeps exactly one reference to a runtime, so the authority's own
## copy cannot be handed to a second, client-side runtime the way it once was
## here - that was the same split ownership a real game must never have,
## worked around rather than tested. `client()` mirrors it instead, the way
## `test_prediction_journal.gd`'s own two-machine pair already does.
var _client_fixture: ASCFixture = null


## An authority, a character, and the entity id joining them.
##
## `parent` is where the character goes; the caller keeps the freeing, the way
## AimingBench does. `mode` is what the runtime replicates by default, which
## most suites want at FULL so that what they assert about is actually sent.
static func built(
	parent: Node,
	named: String = "Networked",
	role: GameplayNetAuthority.Role = GameplayNetAuthority.Role.AUTHORITY,
	mode: GameplayNetReplication.Mode = GameplayNetReplication.Mode.FULL
) -> NetBench:
	var bench: NetBench = NetBench.new()
	bench._parent = parent
	bench.runtime = GameplayNetworkRuntime.new()
	bench.runtime.role = role
	bench.runtime.replication_mode = mode

	bench.fixture = Fixture.create(named)
	parent.add_child(bench.fixture.owner)
	bench.fixture.asc.set_process(false)

	bench.entity = GameplayNetEntityId.of(1)
	bench.runtime.attach(bench.fixture.asc, bench.entity, OWNING_PEER)
	return bench


func asc() -> AbilitySystemComponent:
	return fixture.asc


## The client that owns this bench's entity, on a runtime of its own.
##
## Three suites need one and each was building it the same four ways, with the
## fourth - attaching the same component under the same id - being the one that
## is easy to leave out and hard to read the absence of. The runtime that comes
## back is the caller's to dispose.
##
## What it attaches is `client_asc()`, a mirror of `asc()` under the same id -
## never `asc()` itself, which is already the authority's. A suite driving the
## client's own view of the character - granting it something to run, starting
## or releasing an ability on it - does that through `client_asc()`.
func client() -> GameplayNetworkRuntime:
	var asking: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	asking.role = GameplayNetAuthority.Role.CLIENT
	asking.peer = OWNING_PEER

	_client_fixture = Fixture.create(fixture.owner.name + "Mirror")
	if _parent is GutTest:
		(_parent as GutTest).add_child_autofree(_client_fixture.owner)
	else:
		_parent.add_child(_client_fixture.owner)
	_client_fixture.asc.set_process(false)

	asking.attach(_client_fixture.asc, entity, OWNING_PEER)
	return asking


## The client's own copy of the character, once `client()` has built one.
func client_asc() -> AbilitySystemComponent:
	return _client_fixture.asc if _client_fixture != null else null


## Let go of the runtime. The character is the caller's to free.
func dispose() -> void:
	runtime.dispose()
