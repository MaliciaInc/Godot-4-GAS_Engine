## Whose animation this is, and how the waiting ended.
##
## The failure the whole file is about: two abilities on one character reach for
## the same AnimationPlayer, the second one's `play()` replaces the first's, and
## the first's task goes on waiting for an `animation_finished` that will never
## carry its name. It waited until the ability ended, holding everything the
## ability had taken.
##
## So every test here asks the same thing in a different way - after this, does
## the task know it is over, and does it say why.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Bench = preload("res://test/fixtures/ability_task_bench.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const ABILITY_TAG: StringName = &"Ability.Animating"
const CAST: StringName = &"cast"
const OTHER: StringName = &"other"

var bench: AbilityTaskBench = null
var asc: AbilitySystemComponent = null
var ability: GameplayAbility = null


func before_each() -> void:
	bench = Bench.stand(self, ABILITY_TAG)
	asc = bench.asc
	ability = bench.ability


func after_each() -> void:
	bench = null
	asc = null
	ability = null


func _player_with(names: Array[StringName]) -> AnimationPlayer:
	var player: AnimationPlayer = AnimationPlayer.new()
	var library: AnimationLibrary = AnimationLibrary.new()
	for name: StringName in names:
		library.add_animation(name, Animation.new())
	player.add_animation_library("", library)
	add_child_autofree(player)
	return player


func _casting(player: AnimationMixer) -> AbilityTaskPlayAnimationAndWait:
	return AbilityTaskFactory.play_animation_and_wait(ability, player, CAST)


#region The five ways it can end
## Played to the end.
func test_an_animation_that_finishes_completes() -> void:
	var player: AnimationPlayer = _player_with([CAST] as Array[StringName])
	var task: AbilityTaskPlayAnimationAndWait = _casting(player)

	player.animation_finished.emit(CAST)

	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED)
	assert_eq(task.outcome, AbilityTaskPlayAnimationAndWait.Outcome.COMPLETED)


## Something else started on the surface this task believed it owned.
func test_another_animation_starting_interrupts_it() -> void:
	var player: AnimationPlayer = _player_with([CAST, OTHER] as Array[StringName])
	var task: AbilityTaskPlayAnimationAndWait = _casting(player)

	player.animation_started.emit(OTHER)

	assert_true(task.is_finished(), "it is over rather than waiting for a name never coming")
	assert_eq(task.outcome, AbilityTaskPlayAnimationAndWait.Outcome.INTERRUPTED)


## And the same conclusion reached without any signal at all.
##
## The claim on the surface is the other half of the answer: whatever took the
## animation over, the receipt this task holds is no longer the one the mixer
## records, and the next tick is where it finds out.
func test_losing_the_claim_interrupts_it_on_the_next_tick() -> void:
	var player: AnimationPlayer = _player_with([CAST, OTHER] as Array[StringName])
	var task: AbilityTaskPlayAnimationAndWait = _casting(player)
	assert_true(task.claim.still_holds(), "it took the surface when it started")

	var thief: GameplayAbilitySpec = AbilityFactory.give(asc, Probe.build(&"Ability.Thief"))
	GameplayAnimationOwnership.claim(player, thief.per_actor_instance, OTHER)
	assert_false(task.is_finished(), "nothing has told it yet")

	asc.ability_runtime.advance_time(0.1)

	assert_true(task.is_finished(), "and now it knows")
	assert_eq(task.outcome, AbilityTaskPlayAnimationAndWait.Outcome.INTERRUPTED)


## The ability ended while it was still playing.
func test_the_ability_ending_cancels_it() -> void:
	var player: AnimationPlayer = _player_with([CAST] as Array[StringName])
	var task: AbilityTaskPlayAnimationAndWait = _casting(player)

	ability.end_ability(true)

	assert_eq(task.state, GameplayAbilityTask.State.CANCELLED)
	assert_eq(task.outcome, AbilityTaskPlayAnimationAndWait.Outcome.CANCELLED)


## The ability stopped waiting on purpose and left the body to finish.
func test_blending_out_ends_the_wait_and_leaves_the_animation_alone() -> void:
	var player: AnimationPlayer = _player_with([CAST] as Array[StringName])
	var task: AbilityTaskPlayAnimationAndWait = AbilityTaskFactory.play_animation_and_wait(
		ability, player, CAST, true
	)

	task.blend_out()

	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED, "it got what it needed")
	assert_eq(task.outcome, AbilityTaskPlayAnimationAndWait.Outcome.BLEND_OUT)
	assert_true(player.is_playing(), "and the body finishes the motion")


## There was nothing to play.
func test_an_animation_the_surface_does_not_have_fails() -> void:
	var player: AnimationPlayer = _player_with([OTHER] as Array[StringName])
	var task: AbilityTaskPlayAnimationAndWait = _casting(player)

	assert_true(task.is_finished(), "it does not wait for something that cannot happen")
	assert_eq(task.outcome, AbilityTaskPlayAnimationAndWait.Outcome.FAILED)


## And a node that is not an animation surface at all is the same answer.
func test_a_node_that_is_not_a_surface_fails() -> void:
	var task: AbilityTaskPlayAnimationAndWait = AbilityTaskFactory.play_animation_and_wait(
		ability, null, CAST
	)

	assert_eq(task.outcome, AbilityTaskPlayAnimationAndWait.Outcome.FAILED)
	assert_true(task.is_finished())
#endregion


#region Stopping the surface, and not stopping somebody else's
## `stop_on_cancel` is about the ability's own animation, not about whatever
## replaced it: stopping after a takeover would kill the animation the
## interrupting ability had just started.
func test_a_cancelled_owner_stops_the_surface_but_an_interrupted_one_does_not() -> void:
	var cancelled_player: AnimationPlayer = _player_with([CAST] as Array[StringName])
	var cancelled: AbilityTaskPlayAnimationAndWait = AbilityTaskFactory.play_animation_and_wait(
		ability, cancelled_player, CAST, true
	)
	var taken_player: AnimationPlayer = _player_with([CAST, OTHER] as Array[StringName])
	var taken: AbilityTaskPlayAnimationAndWait = AbilityTaskFactory.play_animation_and_wait(
		ability, taken_player, CAST, true
	)

	taken_player.animation_started.emit(OTHER)
	assert_eq(taken.outcome, AbilityTaskPlayAnimationAndWait.Outcome.INTERRUPTED)
	assert_true(taken_player.is_playing(), "the new owner's animation is left running")

	ability.end_ability(true)
	assert_eq(cancelled.outcome, AbilityTaskPlayAnimationAndWait.Outcome.CANCELLED)
	assert_false(cancelled_player.is_playing(), "its own animation is stopped")


## A task that was already replaced does not take the new claim with it when it
## cleans up.
func test_cleaning_up_after_a_takeover_leaves_the_new_claim_standing() -> void:
	var player: AnimationPlayer = _player_with([CAST, OTHER] as Array[StringName])
	var task: AbilityTaskPlayAnimationAndWait = _casting(player)

	var thief: GameplayAbilitySpec = AbilityFactory.give(asc, Probe.build(&"Ability.Thief"))
	var theirs: GameplayAnimationOwnership = GameplayAnimationOwnership.claim(
		player, thief.per_actor_instance, OTHER
	)
	asc.ability_runtime.advance_time(0.1)

	assert_true(task.is_finished(), "the first one is over")
	assert_true(theirs.still_holds(), "and the surface still says whose it is now")
#endregion


#region Which activation it belongs to
## An instance is reused, so "this ability" does not say whose a playback is.
func test_each_activation_is_stamped_with_its_own_id() -> void:
	var handle: GameplayAbilityHandle = ability.get_ability_handle()
	ability.is_active = false

	asc.try_activate_ability_handle(handle)
	var first: int = ability.activation_id
	ability.is_active = false
	asc.try_activate_ability_handle(handle)

	assert_gt(first, 0, "an activation that ran has an id")
	assert_gt(ability.activation_id, first, "and the next one is not the same id")


## The claim carries it, so the previous activation cannot mistake a new
## activation's animation for its own.
func test_a_new_activation_does_not_inherit_the_previous_ones_claim() -> void:
	var player: AnimationPlayer = _player_with([CAST] as Array[StringName])
	var mine: GameplayAnimationOwnership = GameplayAnimationOwnership.claim(player, ability, CAST)
	ability.activation_id += 1

	var theirs: GameplayAnimationOwnership = GameplayAnimationOwnership.claim(
		player, ability, CAST
	)

	assert_false(mine.same_as(theirs), "the same instance, a different activation")
	assert_false(mine.still_holds(), "so the older receipt is no longer the one held")
	assert_true(theirs.still_holds())
#endregion


#region One surface over two kinds of node
func _tree_with(state: StringName) -> AnimationTree:
	var machine: AnimationNodeStateMachine = AnimationNodeStateMachine.new()
	machine.add_node(state, AnimationNodeAnimation.new())
	var tree: AnimationTree = AnimationTree.new()
	tree.tree_root = machine
	add_child_autofree(tree)
	return tree


## A player is asked whether it has the clip; a tree, whether its state machine
## has the state. A task that asked a tree the player's question would refuse
## every animation the tree has.
func test_the_surface_asks_each_kind_of_node_its_own_question() -> void:
	var player: AnimationPlayer = _player_with([CAST] as Array[StringName])
	var tree: AnimationTree = _tree_with(CAST)

	var over_player: GameplayAnimationSurface = GameplayAnimationSurface.of(player)
	var over_tree: GameplayAnimationSurface = GameplayAnimationSurface.of(tree)

	assert_false(over_player.drives_a_state_machine(), "a player is played")
	assert_true(over_tree.drives_a_state_machine(), "a tree is travelled")
	assert_true(over_player.can_play(CAST))
	assert_true(over_tree.can_play(CAST), "the state machine has that state")
	assert_false(over_tree.can_play(OTHER), "and does not have that one")


## A node that animates nothing is not a surface, rather than a surface that
## does nothing: an ability told yes by a silent no-op would wait for ever.
func test_a_node_that_animates_nothing_is_not_a_surface() -> void:
	var plain: Node = autofree(Node.new())
	assert_null(GameplayAnimationSurface.of(plain))
	assert_null(GameplayAnimationSurface.of(null))


func test_a_player_surface_plays_stops_and_says_what_is_playing() -> void:
	var player: AnimationPlayer = _player_with([CAST] as Array[StringName])
	var surface: GameplayAnimationSurface = GameplayAnimationSurface.of(player)

	assert_true(surface.play(CAST))
	assert_eq(surface.now_playing(), CAST)

	surface.halt()
	assert_ne(surface.now_playing(), CAST, "stopped is not playing")
	assert_false(surface.play(OTHER), "and an animation it does not have is refused")
#endregion
