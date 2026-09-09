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


## Let go of the runtime. The character is the caller's to free.
func dispose() -> void:
	runtime.dispose()
