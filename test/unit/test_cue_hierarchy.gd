## Which cue answers a request, and what the cue is handed when it does.
##
## A game announces what happened, not what it has art for. `Cue.Damage.Fire`
## is a reasonable thing to say about a fireball and a silly thing to demand a
## separate scene for, so a request nothing answers falls back up its own family
## until something does - and a project that wants a branch to stay silent says
## so once rather than binding every leaf under it to an empty scene.
##
## Everything here goes through the real GameplayCueManager autoload, with
## recording cues injected into its own maps the way a populated registry would
## have filled them.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")
const CueProbe = preload("res://test/fixtures/cue_probe.gd")

const ROOT_TAG: StringName = &"Cue.Damage"
const BRANCH: StringName = &"Cue.Damage.Fire"
const LEAF: StringName = &"Cue.Damage.Fire.Critical"
const ELSEWHERE: StringName = &"Cue.Healing"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var manager: CueManagerScript = null
var _bound: Array[StringName] = []
var _silenced: Array[StringName] = []


func before_each() -> void:
	fixture = Fixture.create("CueTarget")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	manager = asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript


## The manager is the project's, shared by every test in the suite, so what a
## test puts into it a test takes back out.
func after_each() -> void:
	for tag: StringName in _bound:
		CueProbe.uninstall(manager, tag)
	for tag: StringName in _silenced:
		CueProbe.unsilence(manager, tag)
	_bound = []
	_silenced = []
	fixture = null
	asc = null
	manager = null


func _bind(tag: StringName) -> void:
	CueProbe.install(manager, tag)
	_bound.append(tag)


func _silence(tag: StringName) -> void:
	CueProbe.silence(manager, tag)
	_silenced.append(tag)


#region Walking up the family
## Bound exactly, answered exactly.
func test_an_exact_binding_answers_its_own_tag() -> void:
	_bind(LEAF)

	assert_eq(manager.resolve_cue_tag(LEAF), LEAF)


## A.B.C, then A.B, then A.
func test_a_request_nobody_bound_falls_back_up_the_family() -> void:
	_bind(ROOT_TAG)

	assert_eq(manager.resolve_cue_tag(LEAF), ROOT_TAG, "two levels up")
	assert_eq(manager.resolve_cue_tag(BRANCH), ROOT_TAG, "and one")


## The nearest binding, not the first one anybody happened to install.
func test_the_nearest_binding_is_the_one_that_answers() -> void:
	_bind(ROOT_TAG)
	_bind(BRANCH)

	assert_eq(manager.resolve_cue_tag(LEAF), BRANCH, "the fireball cue, not the damage cue")
	assert_eq(manager.resolve_cue_tag(ROOT_TAG), ROOT_TAG, "and asking for the general one gets it")


## A family nothing in answers plays nothing, rather than anything.
func test_a_request_nothing_answers_plays_nothing() -> void:
	_bind(ELSEWHERE)

	assert_eq(manager.resolve_cue_tag(LEAF), &"", "a different family is not a fallback")


## The walk does not cross a tag the project marked as the end of it.
##
## Without the mark, this request would be answered by the binding on the
## family above it. The mark is how a project says "nothing plays under here"
## once, instead of binding every leaf to an empty scene.
func test_a_silenced_branch_stops_the_walk_before_its_parent() -> void:
	_bind(ROOT_TAG)
	_silence(BRANCH)

	assert_eq(manager.resolve_cue_tag(LEAF), &"", "it stopped at the branch")
	assert_eq(manager.resolve_cue_tag(BRANCH), &"", "and at the branch itself")
	assert_eq(manager.resolve_cue_tag(ROOT_TAG), ROOT_TAG, "the family above still plays")


## A mark on a tag that does have a binding changes nothing: the binding is
## already where the walk stops.
func test_a_marked_tag_that_is_also_bound_still_plays() -> void:
	_bind(BRANCH)
	_silence(BRANCH)

	assert_eq(manager.resolve_cue_tag(LEAF), BRANCH)
#endregion


#region What the cue is told
## Both tags, because they are two different questions.
func test_a_cue_is_told_what_was_asked_for_and_what_answered() -> void:
	_bind(ROOT_TAG)
	var params: GameplayCueParams = CueProbe.params_for(LEAF, fixture.owner)

	asc.execute_cue(params)

	assert_eq(params.cue_tag, LEAF, "what the game announced")
	assert_eq(params.matched_cue_tag, ROOT_TAG, "and what actually played")
	assert_eq(
		_recorded_matched_tag(), ROOT_TAG, "which is what reached the cue itself"
	)


## The cue the request produced, asked what it was told.
func _recorded_matched_tag() -> StringName:
	for child: Node in fixture.owner.get_children():
		var recording: CueProbe.RecordingPersistentCue = child as CueProbe.RecordingPersistentCue
		if recording != null:
			return recording.last_matched_tag
	return &""


## Stack count and hit travel with the cue, so a cue does not have to resolve a
## handle for an effect that may already be gone by the time it plays.
func test_the_params_carry_the_stack_count_and_the_hit() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var active: ActiveGameplayEffect = Factory.apply(asc, Factory.infinite(no_modifiers))
	active.spec.stack_count = 3
	var landed: bool = active.spec.context.target_data.append_physics_hit({
		&"collider": fixture.owner,
		"position": Vector3(1.0, 2.0, 3.0),
		"normal": Vector3.UP,
	})
	assert_true(landed, "the fixture's hit was accepted")

	var params: GameplayCueParams = asc.effects.cue_params_for(LEAF, active.spec, active.handle)

	assert_eq(params.stack_count, 3, "how many of it were on the target")
	assert_not_null(params.target_hit, "and where it landed")
	assert_eq(params.target_hit.position_3d, Vector3(1.0, 2.0, 3.0))
	assert_eq(params.effect_handle, active.handle, "with the effect it came from")
	assert_eq(params.context, active.spec.context, "and the context behind it")


## The hit handed over is this target's own, not whoever was struck first.
##
## One area effect records a hit per victim in one target data, and the cue
## playing on the second victim must not be told where the first one was
## struck: a decal would align itself to somebody else's surface, and a spark
## would go off across the room.
func test_the_hit_a_cue_gets_is_this_targets_own() -> void:
	var bystander: Node = autofree(Node.new())
	var no_modifiers: Array[GameplayEffectModifier] = []
	var active: ActiveGameplayEffect = Factory.apply(asc, Factory.infinite(no_modifiers))
	var aimed: GameplayAbilityTargetData = active.spec.context.target_data
	assert_true(aimed.append_physics_hit({
		&"collider": bystander,
		"position": Vector3(9.0, 9.0, 9.0),
		"normal": Vector3.UP,
	}), "somebody else was hit first")
	assert_true(aimed.append_physics_hit({
		&"collider": fixture.owner,
		"position": Vector3(1.0, 2.0, 3.0),
		"normal": Vector3.UP,
	}), "and then this target was")

	var params: GameplayCueParams = asc.effects.cue_params_for(LEAF, active.spec, active.handle)

	assert_eq(
		params.target_hit.position_3d, Vector3(1.0, 2.0, 3.0),
		"where this one was hit, not where the other one was"
	)


## An effect that hit nothing in particular carries no hit, rather than an
## empty one that reads as a real impact at the origin.
func test_an_effect_with_no_hit_for_this_target_carries_none() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var active: ActiveGameplayEffect = Factory.apply(asc, Factory.infinite(no_modifiers))

	var params: GameplayCueParams = asc.effects.cue_params_for(LEAF, active.spec, active.handle)

	assert_null(params.target_hit)
	assert_eq(params.stack_count, 1, "one of it, which is what a fresh application is")
#endregion


#region Pooling leaves nothing behind
## A cue on its way into the pool lets go of the run that just ended.
##
## What it was holding was not only its own params: through them, the target
## node, the effect context and the handle of an effect that is over. A dormant
## cue asked what it was doing would have answered with somebody else's cast,
## and nothing in the scene could be freed while the pool kept the reference.
func test_a_pooled_cue_holds_nothing_from_its_last_run() -> void:
	_bind(ROOT_TAG)
	var handle: GameplayCueHandle = manager.activate_persistent_cue(
		CueProbe.params_for(ROOT_TAG, fixture.owner)
	)
	var playing: GameplayCueNotify = _the_cue_on_the_target()
	assert_not_null(playing.current_params, "it knows what it is doing while it runs")

	manager.deactivate_persistent_cue(handle, CueProbe.params_for(ROOT_TAG, fixture.owner))

	assert_eq(manager.get_pooled_count(ROOT_TAG), 1, "it went back into the pool")
	assert_null(playing.current_params, "and it went in holding nothing")


## And the next run out of the pool answers with its own params, not the last
## run's - the same instance, a different cast.
func test_a_reused_cue_answers_with_the_new_run() -> void:
	_bind(ROOT_TAG)
	var first: GameplayCueHandle = manager.activate_persistent_cue(
		CueProbe.params_for(ROOT_TAG, fixture.owner)
	)
	var instance: GameplayCueNotify = _the_cue_on_the_target()
	manager.deactivate_persistent_cue(first, CueProbe.params_for(ROOT_TAG, fixture.owner))

	var second_params: GameplayCueParams = CueProbe.params_for(LEAF, fixture.owner)
	manager.activate_persistent_cue(second_params)

	assert_same(_the_cue_on_the_target(), instance, "the pool gave the same instance back")
	assert_same(instance.current_params, second_params, "and it is running the new cast")
	assert_eq(instance.current_params.cue_tag, LEAF, "which asked for something else")


func _the_cue_on_the_target() -> GameplayCueNotify:
	for child: Node in fixture.owner.get_children():
		var cue: GameplayCueNotify = child as GameplayCueNotify
		if cue != null:
			return cue
	return null
#endregion
