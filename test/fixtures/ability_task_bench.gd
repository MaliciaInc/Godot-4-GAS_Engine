## Everything the F5.4.3 task tests stand on.
##
## An entity with an ASC, a probe ability granted and marked running so there is
## something a task can be owned by and cancelled with, and the props those
## tasks move around: a body, a spatial, an animation tree, a scene to spawn.
##
## One bench rather than a `before_each` in each file. The nine tasks are
## covered by two files - one asking the same contract of all of them, one
## asking what each is for - and both need exactly this standing. Two spellings
## of it drift the first time either is tuned, and nothing would report it.
##
## Every prop is parented to the test that asked for it, because a node nobody
## owns is an orphan and the suite's verdict counts those.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskBench extends RefCounted

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var ability: GameplayAbility = null


## Stand one up inside `host`, with a probe ability already running.
##
## `set_process(false)` because these tests advance the clock themselves: a
## component ticking on its own would move a task between the line that sets
## something up and the line that reads it.
static func stand(host: GutTest, tag: StringName) -> AbilityTaskBench:
	var bench: AbilityTaskBench = AbilityTaskBench.new()
	bench.fixture = Fixture.create("Waiter")
	host.add_child_autofree(bench.fixture.owner)
	bench.asc = bench.fixture.asc
	bench.asc.set_process(false)
	var spec: GameplayAbilitySpec = AbilityFactory.give(bench.asc, Probe.build(tag))
	bench.ability = spec.per_actor_instance
	bench.ability.is_active = true
	return bench


## A scene with one node in it, packed from a template that is freed at once:
## a spawn task needs something to instantiate, not something to keep.
static func scene() -> PackedScene:
	var template: Node = Node.new()
	template.name = "Spawned"
	var packed: PackedScene = PackedScene.new()
	packed.pack(template)
	template.free()
	return packed


static func body(host: GutTest) -> Node2D:
	var made: Node2D = Node2D.new()
	host.add_child_autofree(made)
	return made


static func spatial(host: GutTest) -> Node3D:
	var made: Node3D = Node3D.new()
	host.add_child_autofree(made)
	return made


## A player holding one empty clip per name, so a task has something real to
## ask for and a test can drive `animation_finished` by hand.
static func player(host: GutTest, names: Array[StringName]) -> AnimationPlayer:
	var made: AnimationPlayer = AnimationPlayer.new()
	var library: AnimationLibrary = AnimationLibrary.new()
	for name: StringName in names:
		library.add_animation(name, Animation.new())
	made.add_animation_library("", library)
	host.add_child_autofree(made)
	return made


static func tree(host: GutTest) -> AnimationTree:
	var made: AnimationTree = AnimationTree.new()
	host.add_child_autofree(made)
	return made
