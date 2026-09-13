## One entity, registered under the same id on every machine a `NetLink` walk
## is driving - which is what every peer being told about a character looks
## like, and what two suites were building the same way by hand.
##
## `seed`, when given one, runs on each machine's own copy right after it is
## created and before it is attached - the one place a suite that wants every
## copy starting from the same numbers can reach all of them, since each
## machine gets its own separate fixture rather than sharing one.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name NetLinkEntity extends RefCounted

const Fixture = preload("res://test/fixtures/asc_fixture.gd")


static func everywhere(
	host: GutTest,
	machines: Array[GameplayNetworkRuntime],
	value: int,
	owner_peer: int,
	seed: Callable = Callable()
) -> GameplayNetEntityId:
	var id: GameplayNetEntityId = GameplayNetEntityId.of(value)
	for machine: GameplayNetworkRuntime in machines:
		var fixture: ASCFixture = Fixture.create("Entity%d" % value)
		host.add_child_autofree(fixture.owner)
		fixture.asc.set_process(false)
		if seed.is_valid():
			seed.call(fixture)
		machine.attach(fixture.asc, id, owner_peer)
	return id
