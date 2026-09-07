## What is left behind when a component is reset, and when it dies.
##
## Two different endings, and the whole point is that they are different.
## `cleanup()` is a reset: the component is still alive and usable, so it must
## put back everything a fresh one would have and nothing else. `dispose()` is
## terminal: the component is on its way out, and what it owes is that nothing
## it wired up outlives it.
##
## The second one is a memory bug no assertion about behaviour can see. The
## runtimes hold each other both ways - the component points at each of them,
## and each points back at the component and at its siblings - so the whole
## graph kept itself alive at a refcount nothing could bring to zero. A scene
## that spawns and frees entities leaked every one of them, and every test in
## this suite passed the entire time.
##
## So these ask the only question that can see it: after the component is gone
## and the frame is over, does a weak reference still resolve.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Owner")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
## An ability that stays active once started, granted per actor.
##
## Per actor is the policy that puts a real node under the component, and
## staying active is what gives the reset something to actually retire: an
## ability that ends in the frame it starts is gone before anybody asks.
func _grant() -> GameplayAbilitySpec:
	var ability: StaysActiveAbility = StaysActiveAbility.new()
	ability.instancing_policy = GameplayAbility.InstancingPolicy.PER_ACTOR
	return AbilityFactory.give(asc, ability)


## Let Godot actually run the deferred frees a teardown queues.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _ability_children() -> int:
	var count: int = 0
	for child: Node in asc.get_children():
		if child is GameplayAbility:
			count += 1
	return count
#endregion


#region Reset
## A reset takes the instanced abilities out of the tree, not just out of a map.
##
## B06. `clear()` emptied the registry and left the nodes parented to the
## component: the ability was gone as far as anything could ask, and still there
## as far as the scene tree was concerned.
func test_a_reset_retires_the_instances_it_created() -> void:
	var spec: GameplayAbilitySpec = _grant()
	asc.ability_runtime.try_activate(spec.handle)
	assert_gt(_ability_children(), 0, "the grant put an instance under the component")

	asc.cleanup()
	await _settle()

	assert_eq(_ability_children(), 0, "and the reset took it back out")


## An ability somebody kept a reference to stops pointing back at the component.
##
## Whoever held it is holding a corpse either way; what must not happen is that
## the corpse keeps the component alive, or that it goes on answering questions
## about a run that is over.
func test_an_ability_held_across_a_reset_no_longer_points_at_anything() -> void:
	var spec: GameplayAbilitySpec = _grant()
	asc.ability_runtime.try_activate(spec.handle)
	var instance: GameplayAbility = asc.ability_runtime.instancing.instance_for_activation(spec)
	assert_not_null(instance, "there is an instance to hold")

	asc.cleanup()

	# Asked in the frame the reset happened. The node is queued to be freed and
	# is still readable, and that is exactly the window that matters: a
	# back-reference left behind here is one somebody's held copy would use to
	# keep the whole component alive.
	assert_null(instance.owner_asc, "it no longer points at the component")
	assert_null(instance.current_spec, "nor at the activation it was serving")

	await _settle()

	var still_there: bool = is_instance_valid(instance)
	assert_false(still_there, "and by the next frame it is gone")


## A reset leaves a component that still works.
func test_an_ability_can_be_granted_again_after_a_reset() -> void:
	_grant()
	asc.cleanup()
	await _settle()

	var again: GameplayAbilitySpec = _grant()

	assert_not_null(again, "the grant went through")
	assert_eq(
		asc.ability_runtime.try_activate(again.handle).status,
		GameplayAbilityActivationResult.Status.SUCCESS,
		"and the ability runs"
	)


## Resetting twice is resetting once.
func test_a_second_reset_changes_nothing_and_raises_nothing() -> void:
	_grant()
	asc.cleanup()
	await _settle()
	var after_first: int = _ability_children()

	asc.cleanup()
	await _settle()

	assert_eq(_ability_children(), after_first, "the second reset found nothing to do")
	assert_eq(asc.ability_runtime.specs().size(), 0, "and left it empty")


## Nothing an ability started survives the reset.
func test_no_task_outlives_a_reset() -> void:
	var spec: GameplayAbilitySpec = _grant()
	asc.ability_runtime.try_activate(spec.handle)
	var instance: GameplayAbility = asc.ability_runtime.instancing.instance_for_activation(spec)
	assert_not_null(instance.wait_delay(10.0), "a task was started")
	assert_gt(asc.ability_runtime.tasks.active_count(), 0, "and is running")

	asc.cleanup()
	await _settle()

	assert_eq(asc.ability_runtime.tasks.active_count(), 0, "and none is now")
#endregion


#region Death
## Every runtime a component wired up dies with it.
##
## B05. The only assertion that can see the leak, because the graph was
## internally consistent the whole time: the component pointed at the runtimes,
## the runtimes pointed back, and every refcount stayed above zero forever.
##
## Weak references are taken to the four the master names, two of which are
## collaborators a runtime owns - the ones that held a back-reference of their
## own, which is what made this a cycle rather than a chain.
func test_every_runtime_dies_with_the_component_that_wired_it() -> void:
	var doomed: ASCFixture = Fixture.create("Doomed")
	add_child(doomed.owner)
	doomed.asc.set_process(false)

	var watched: Dictionary[String, WeakRef] = {
		"effects": weakref(doomed.asc.effects),
		"effects.stacking": weakref(doomed.asc.effects.stacking),
		"ability_runtime": weakref(doomed.asc.ability_runtime),
		"ability_runtime.instancing": weakref(doomed.asc.ability_runtime.instancing),
	}
	for named: String in watched:
		var held: WeakRef = watched[named]
		var alive: bool = held.get_ref() != null
		assert_true(alive, "%s is alive to begin with" % named)

	doomed.owner.free()
	doomed = null
	await _settle()

	for named: String in watched:
		var held: WeakRef = watched[named]
		var survived: bool = held.get_ref() != null
		assert_false(survived, "%s outlived the component" % named)


## And it holds for a scene that does it a thousand times.
##
## One entity dying proves the references were severed. A thousand proves
## nothing accumulates somewhere else on the way - a registry, a static, a
## signal connection keeping its own copy - which is the shape this leak
## actually had in a running game.
func test_a_thousand_components_leave_nothing_behind() -> void:
	# A warm-up first: the very first component of a process builds caches that
	# are meant to be shared, and counting those would read as growth.
	for _warm: int in 5:
		var warm: ASCFixture = Fixture.create("Warm")
		add_child(warm.owner)
		warm.asc.set_process(false)
		warm.owner.free()
	await _settle()

	var last: WeakRef = null
	for _round: int in 1000:
		var made: ASCFixture = Fixture.create("Churned")
		made.asc.set_process(false)
		add_child(made.owner)
		last = weakref(made.asc.effects)
		made.owner.free()
		made = null

	await _settle()

	var survived: bool = last.get_ref() != null
	assert_false(survived, "the last one's effect runtime outlived it")
	for child: Node in get_children():
		assert_false(
			String(child.name).begins_with("Churned"),
			"and no entity was left in the tree"
		)
#endregion
