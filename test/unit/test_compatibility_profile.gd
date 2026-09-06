## Which set of contracts a component answers by, and what it answers by default.
##
## The profile exists because some of what GAS_Engine does on purpose is not
## what Unreal does, and both have to keep working. It is data rather than a
## flag each runtime reads its own way: two runtimes asking the same profile
## agree, and two runtimes each deciding what "compatible" means do not.
##
## The default is the whole risk. A phase that adds a compatibility mode and
## quietly switches existing projects into it has changed every ability anybody
## already shipped, so the assertion that matters most here is the dullest one:
## nothing asked for, nothing changed.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest


#region What a fresh one is
## A profile nobody configured is the engine's own semantics.
func test_a_new_profile_is_godot_native() -> void:
	var profile: GameplayCompatibilityProfile = GameplayCompatibilityProfile.new()

	assert_eq(
		profile.mode,
		GameplayCompatibilityProfile.Mode.GODOT_NATIVE,
		"the default mode is the one that changes nothing"
	)
	assert_false(profile.is_ue_5_7(), "so it does not claim Unreal's contracts")


## And a component nobody configured answers the same way.
##
## This is the one that protects projects that already exist: installing the
## phase must not move a single ability onto a different contract.
func test_a_new_component_does_not_use_unreal_contracts() -> void:
	var fixture: ASCFixture = ASCFixture.create()
	add_child_autofree(fixture.owner)

	assert_not_null(
		fixture.asc.compatibility_profile, "a component always has a profile to ask"
	)
	assert_false(
		fixture.asc.uses_ue_5_7_contracts(),
		"and by default it is not answering by Unreal's"
	)


## Two components do not share one profile.
##
## An exported Resource default is one object unless each component gets its
## own, and a shared one would mean putting a single entity onto the UE profile
## moved every other entity in the scene with it.
func test_two_components_do_not_share_one_profile() -> void:
	var first: ASCFixture = ASCFixture.create("First")
	var second: ASCFixture = ASCFixture.create("Second")
	add_child_autofree(first.owner)
	add_child_autofree(second.owner)

	first.asc.compatibility_profile.mode = GameplayCompatibilityProfile.Mode.UE_5_7

	assert_true(first.asc.uses_ue_5_7_contracts(), "the one that was asked, answers so")
	assert_false(
		second.asc.uses_ue_5_7_contracts(),
		"and the one nobody touched is still on its own semantics"
	)
#endregion


#region Asking for the other one
## Set to UE 5.7, the profile and the component both say so.
func test_a_component_told_to_use_unreal_contracts_says_so() -> void:
	var fixture: ASCFixture = ASCFixture.create()
	add_child_autofree(fixture.owner)

	fixture.asc.compatibility_profile.mode = GameplayCompatibilityProfile.Mode.UE_5_7

	assert_true(
		fixture.asc.compatibility_profile.is_ue_5_7(), "the profile carries the answer"
	)
	assert_true(fixture.asc.uses_ue_5_7_contracts(), "and the component passes it on")


## A component with no profile at all is Godot-native, not a crash.
##
## Somebody can clear the field in the inspector, and a runtime asking a null
## profile mid-activation would take the ability down with it. Absent means the
## default, which is the answer that changes nothing.
func test_a_component_with_no_profile_falls_back_to_godot_native() -> void:
	var fixture: ASCFixture = ASCFixture.create()
	add_child_autofree(fixture.owner)

	fixture.asc.compatibility_profile = null

	assert_false(
		fixture.asc.uses_ue_5_7_contracts(),
		"no profile is not Unreal's contract, and not an error either"
	)
#endregion
