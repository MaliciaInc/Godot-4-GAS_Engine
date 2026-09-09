## A character with a body and an ability, for a suite that is about aiming.
##
## Three suites need the same four things before they can ask a provider
## anything: a component, a Node3D to be its avatar so positions mean something,
## the two joined, and an ability for a provider to belong to. Written out in
## each of them that is four lines of setup three times, and the second copy is
## the one that stops matching the day the avatar wiring changes.
##
## The caller still adds the nodes to its own tree, because who frees them is
## the test's business and GutTest's `add_child_autofree` is the test's own.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name AimingBench extends RefCounted

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

var fixture: ASCFixture = null

## The body the component acts on. A Node3D rather than a plain Node, because
## every question a targeting suite asks is about where something is.
var body: Node3D = null

var ability: GameplayAbility = null


## Everything an aiming test needs, wired but not parented.
##
## `parent` is where the two nodes go. Handed in rather than found, so the test
## keeps the freeing.
static func built(parent: Node, named: String = "Aimer") -> AimingBench:
	var bench: AimingBench = AimingBench.new()
	bench.fixture = Fixture.create(named)
	bench.body = Node3D.new()
	bench.body.name = "Body"
	parent.add_child(bench.fixture.owner)
	parent.add_child(bench.body)
	bench.fixture.asc.init_ability_actor_info(bench.fixture.owner, bench.body)
	bench.ability = TestAbilityFactory.give(
		bench.fixture.asc, Probe.build(&"Ability.Aiming")
	).per_actor_instance
	return bench


func asc() -> AbilitySystemComponent:
	return fixture.asc
