## Cues an ability starts that outlive the call, and the promise that it cannot
## leave one running.
##
## A one-shot cue is over when it is over. A persistent one is not - a channel's
## beam, an aura while a stance is held - which means it can be left behind on a
## character whose ability ended three fights ago. Every way an ability can stop
## is checked here, because a cleanup that only ran on the tidy path is a
## cleanup that runs on the path nobody takes.
##
## The second promise is whose cue it is: one activation ending must not take
## away another's, which is the failure a component-wide list of running cues
## produces and the reason the ledger belongs to the activation.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")
const CueProbe = preload("res://test/fixtures/cue_probe.gd")

const AURA: StringName = &"Cue.Ability.Aura"
const HELD: StringName = &"Ability.Held"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var manager: CueManagerScript = null


func before_each() -> void:
	fixture = Fixture.create("Channeller")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	manager = asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript
	CueProbe.install(manager, AURA)


func after_each() -> void:
	manager.remove_all_cues(fixture.owner)
	CueProbe.uninstall(manager, AURA)
	fixture = null
	asc = null
	manager = null


#region Getting there
## A channelling ability, so the activation is still going when the test looks.
func _channelling() -> ChannelingAbility:
	var ability: ChannelingAbility = ChannelingAbility.new()
	ability.ability_tags = [HELD] as Array[StringName]
	return ability


func _granted() -> ChannelingAbility:
	var spec: GameplayAbilitySpec = TestAbilityFactory.give(asc, _channelling())
	return spec.per_actor_instance as ChannelingAbility


## How many persistent cues are running on this character.
func _running() -> int:
	return manager._playbacks.ids_for(fixture.owner).size()
#endregion


## Every way an ability stops takes its cues with it.
##
##     [how it stopped, what to do to it]
func _ending_cases() -> Array:
	return [["it ended normally", false], ["it was cancelled", true]]


func test_an_ability_takes_its_persistent_cues_with_it(
	case: Array = use_parameters(_ending_cases())
) -> void:
	var described: String = case[0]
	var cancelled: bool = case[1]

	var ability: ChannelingAbility = _granted()
	ability.try_activate()
	ability.activate_persistent_cue(AURA)

	assert_eq(_running(), 1, "%s: the cue is running" % described)

	if cancelled:
		ability.abort_ability()
	else:
		ability.end_ability(false)

	assert_eq(_running(), 0, "%s: and stopped when the ability did" % described)


## One activation ending never takes away another's cue.
##
## The failure this rules out is the one a component-wide list of running cues
## produces: a second ability ending would end the first one's aura, and neither
## of them would have any way to notice.
func test_one_activation_never_ends_anothers_cue() -> void:
	var mine: ChannelingAbility = _granted()
	var theirs: ChannelingAbility = _granted()
	mine.try_activate()
	theirs.try_activate()
	mine.activate_persistent_cue(AURA)
	theirs.activate_persistent_cue(AURA)

	assert_eq(_running(), 2, "both are running")

	theirs.end_ability(false)

	assert_eq(_running(), 1, "one of them ended and one of them did not")


## An ability can stop one of its own early, and cannot stop one that is not.
func test_an_ability_stops_its_own_cue_and_only_its_own() -> void:
	var mine: ChannelingAbility = _granted()
	var theirs: ChannelingAbility = _granted()
	mine.try_activate()
	theirs.try_activate()
	var handle: GameplayCueHandle = mine.activate_persistent_cue(AURA)

	assert_false(
		theirs.deactivate_persistent_cue(handle),
		"a handle from somebody else's activation is refused"
	)
	assert_eq(_running(), 1, "and nothing was ended by asking")

	assert_true(mine.deactivate_persistent_cue(handle), "its own is not")
	assert_eq(_running(), 0, "and that one is over")


## Clearing the whole component ends everything, whoever started it.
##
## Through the component's own door, because a character being reset does not
## know which of its cues came from an ability and which from an effect.
func test_the_component_can_end_every_cue_on_it() -> void:
	var ability: ChannelingAbility = _granted()
	ability.try_activate()
	ability.activate_persistent_cue(AURA)
	Factory.apply(
		asc,
		Factory.with_persistent_cues(
			Factory.infinite([] as Array[GameplayEffectModifier]), [AURA] as Array[StringName]
		)
	)

	assert_eq(_running(), 2, "one from an ability and one from an effect")

	asc.remove_all_gameplay_cues()

	assert_eq(_running(), 0, "and the component ended both")
