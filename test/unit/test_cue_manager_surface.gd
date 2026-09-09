## What the cue manager can be asked, beyond "play this".
##
## Four things that only make sense once cues outlive the call that started
## them: how many of one may run at once, what is running on a character, how to
## end all of it when that character goes away, and how to pay for the
## instantiating before the fight rather than during it.
##
## And the one boundary that is not about the manager at all: a target that
## implements `handle_gameplay_cue` hears about its own cues, beside whatever
## was bound to the tag rather than instead of it.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")
const CueProbe = preload("res://test/fixtures/cue_probe.gd")

const IMPACT: StringName = &"Cue.Surface.Impact"
const AURA: StringName = &"Cue.Surface.Aura"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var manager: CueManagerScript = null


## A target that wants to hear about its own cues.
##
## Duck-typed, which is the contract: a target is whatever the game already had,
## and an interface it had to extend would be a class in front of every one.
class ListeningTarget extends Node:
	var heard: Array[StringName] = []
	var events: Array[int] = []

	func handle_gameplay_cue(
		tag: StringName, event: GameplayCueNotify.Event, _params: GameplayCueParams
	) -> void:
		heard.append(tag)
		events.append(int(event))


func before_each() -> void:
	fixture = Fixture.create("Struck")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	manager = asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript
	CueProbe.install(manager, IMPACT)
	CueProbe.install(manager, AURA)


func after_each() -> void:
	manager.remove_all_cues(fixture.owner)
	CueProbe.uninstall(manager, IMPACT)
	CueProbe.uninstall(manager, AURA)
	# The flags are read off the scene once and cached by tag, and these tags
	# are this suite's own - left behind, the next suite to bind the same
	# name would inherit whatever this one set.
	manager.catalog.flags.erase(IMPACT)
	manager.catalog.flags.erase(AURA)
	fixture = null
	asc = null
	manager = null


#region Getting there
func _params(tag: StringName, instigator: Node = null) -> GameplayCueParams:
	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = tag
	params.instigator = instigator if instigator != null else fixture.owner
	params.target = fixture.owner
	return params


## What the manager believes this cue declares, so a test can set one the way
## a scene would have.
func _declared(tag: StringName) -> GameplayCueFlags:
	return manager.catalog.flags_for(tag)


## How many persistent cues are running on this suite's own character.
##
## Not how many are running at all: the manager is the project's, shared by
## every suite, and a count of everything in it is a count of somebody else's
## cues as much as of these.
func _running_here() -> int:
	return manager._playbacks.ids_for(fixture.owner).size()
#endregion


#region How many of one may run
## A unique cue started twice by one instigator is one cue.
##
## And the handle that comes back is the one already running, not a second one:
## a caller holding a handle that ends nothing would have no way to end the cue
## it thinks it started.
func test_a_unique_cue_started_twice_by_one_instigator_runs_once() -> void:
	_declared(AURA).unique_per_instigator = true

	var first: GameplayCueHandle = asc.activate_persistent_cue(_params(AURA))
	var second: GameplayCueHandle = asc.activate_persistent_cue(_params(AURA))

	assert_true(first.is_valid(), "the first one started")
	assert_eq(second.id, first.id, "and the second answered with the same playback")
	assert_eq(_running_here(), 1, "one running cue, not two")


## Two instigators are two cues, even when the cue is unique per instigator -
## which is what "per instigator" means and the half a test of the first arm
## alone would let through.
func test_two_instigators_get_one_unique_cue_each() -> void:
	_declared(AURA).unique_per_instigator = true
	var other: Node = Node.new()
	add_child_autofree(other)

	var mine: GameplayCueHandle = asc.activate_persistent_cue(_params(AURA))
	var theirs: GameplayCueHandle = asc.activate_persistent_cue(_params(AURA, other))

	assert_ne(theirs.id, mine.id, "two archers, two burning arrows")
	assert_eq(_running_here(), 2, "both are running")
#endregion


#region What is running, and ending all of it
func test_a_running_cue_can_be_asked_about_and_ended_with_the_rest() -> void:
	asc.activate_persistent_cue(_params(AURA))

	assert_true(manager.is_cue_active(fixture.owner, AURA), "it is running")
	assert_false(
		manager.is_cue_active(fixture.owner, IMPACT), "and only the one that is"
	)

	manager.remove_all_cues(fixture.owner)

	assert_false(manager.is_cue_active(fixture.owner, AURA), "and now nothing is")
	assert_eq(_running_here(), 0, "with no record left behind")
#endregion


#region Paying for it early
## Preallocation fills the pool from what each cue asked for.
##
## The pool is the observation rather than a counter of its own: what a project
## buys by calling this is that the next activation takes an instance instead of
## instantiating a scene.
func test_preallocation_fills_the_pool_from_what_each_cue_asked_for() -> void:
	_declared(IMPACT).preallocate = 3
	assert_eq(manager.get_pooled_count(IMPACT), 0, "nothing is made in advance by default")

	manager.preallocate_from_registry()

	assert_eq(manager.get_pooled_count(IMPACT), 3, "three of them, made early")
	assert_eq(
		manager.get_pooled_count(AURA), 0, "and none of the cue that asked for none"
	)
#endregion


#region The target hears too
## Both receive: the binding plays, and the target is told.
##
## Not one or the other. A target that wants to flash red when it is hit should
## not have to become the thing that plays the impact, and a project that binds
## a scene should not lose the chance to react in code.
func test_a_target_that_says_so_hears_about_its_own_cues() -> void:
	var listening: ListeningTarget = ListeningTarget.new()
	add_child_autofree(listening)
	var params: GameplayCueParams = _params(IMPACT)
	params.target = listening

	manager.execute_cue(params)

	assert_eq(listening.heard, [IMPACT] as Array[StringName], "the target was told")
	assert_eq(
		listening.events,
		[int(GameplayCueNotify.Event.EXECUTED)] as Array[int],
		"and which of the four moments it was"
	)
	assert_eq(
		CueProbe.executions(manager, listening, IMPACT), 1, "and the binding played too"
	)
#endregion
