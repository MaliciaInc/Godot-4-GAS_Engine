## The GameplayEffectComponent framework: hook order, preparation/discard,
## preflight refusal atomicity, and the six concrete components Task 8 adds.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const ATTACK: StringName = &"attack"
const TOLERANCE: float = 0.0001

var source: ASCFixture = null
var target: ASCFixture = null


## Records what happened to it, into a log shared across every
## RecordingComponent on one effect, so a test can assert order and coverage
## without inspecting private runtime state. Every forced failure is opt-in
## and off by default.
class RecordingComponent extends GameplayEffectComponent:
	var entries: Array[String] = []
	var label: String = ""
	var deny_can_apply: bool = false
	var reject_prepare: bool = false
	var validation_invalid: bool = false
	var prepared_state: GameplayEffectComponentState = null

	func validate_definition(_owner_effect: GameplayEffect) -> GameplayEffectComponentValidationResult:
		entries.append(label + ":validate")
		if validation_invalid:
			return GameplayEffectComponentValidationResult.invalid(self, "test-forced")
		return GameplayEffectComponentValidationResult.ok()

	func can_apply(_request: GameplayEffectComponentApplyRequest) -> GameplayEffectComponentDecision:
		entries.append(label + ":can_apply")
		if deny_can_apply:
			return GameplayEffectComponentDecision.deny("test-forced")
		return GameplayEffectComponentDecision.allow()

	func prepare_application(
		_request: GameplayEffectComponentApplyRequest
	) -> GameplayEffectComponentPreparationResult:
		entries.append(label + ":prepare")
		if reject_prepare:
			return GameplayEffectComponentPreparationResult.rejected("test-forced")
		return GameplayEffectComponentPreparationResult.ok(prepared_state)

	func discard_prepared(_state: GameplayEffectComponentState) -> void:
		entries.append(label + ":discard")

	func on_effect_applied(_context: GameplayEffectComponentRuntimeContext) -> void:
		entries.append(label + ":applied")

	func on_effect_removed(_context: GameplayEffectComponentRemovalContext) -> void:
		entries.append(label + ":removed")


class AlwaysDeniesRequirement extends GameplayEffectApplicationRequirement:
	func can_apply(_request: GameplayEffectComponentApplyRequest) -> GameplayEffectComponentDecision:
		return GameplayEffectComponentDecision.deny("never")


func before_each() -> void:
	source = Fixture.create("Source")
	target = Fixture.create("Target")
	add_child_autofree(source.owner)
	add_child_autofree(target.owner)


func after_each() -> void:
	source = null
	target = null


func _recording(label: String, entries: Array[String]) -> RecordingComponent:
	var component: RecordingComponent = RecordingComponent.new()
	component.label = label
	component.entries = entries
	return component


#region Hook order and preparation
func test_components_run_in_declared_order() -> void:
	var entries: Array[String] = []
	var effect: GameplayEffect = Factory.infinite([])
	effect.components = [_recording("first", entries), _recording("second", entries)]

	Factory.apply(target.asc, effect, source.owner)

	assert_eq(entries, [
		"first:validate", "second:validate",
		"first:can_apply", "second:can_apply",
		"first:prepare", "second:prepare",
		"first:applied", "second:applied",
	] as Array[String])


func test_prepared_states_are_indexed_by_component_index() -> void:
	var state_a: GameplayEffectComponentState = GameplayEffectComponentState.new()
	var state_b: GameplayEffectComponentState = GameplayEffectComponentState.new()
	var comp_a: RecordingComponent = _recording("a", [])
	comp_a.prepared_state = state_a
	var comp_b: RecordingComponent = _recording("b", [])
	comp_b.prepared_state = state_b

	var effect: GameplayEffect = Factory.infinite([])
	effect.components = [comp_a, comp_b]

	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect, source.owner)

	assert_eq(active.component_states.size(), 2)
	assert_same(active.component_states[0], state_a)
	assert_same(active.component_states[1], state_b)


func test_a_prepare_rejection_discards_earlier_states_in_reverse_order() -> void:
	var entries: Array[String] = []
	var first: RecordingComponent = _recording("first", entries)
	var second: RecordingComponent = _recording("second", entries)
	second.reject_prepare = true

	var effect: GameplayEffect = Factory.infinite([])
	effect.components = [first, second]

	var applied: ActiveGameplayEffect = Factory.apply(target.asc, effect, source.owner)

	assert_null(applied, "the whole application is refused")
	assert_eq(entries, [
		"first:validate", "second:validate",
		"first:can_apply", "second:can_apply",
		"first:prepare", "second:prepare",
		"first:discard",
	] as Array[String], "second never prepared, so only first is discarded")


func test_an_evaluator_failure_discards_every_prepared_state() -> void:
	var entries: Array[String] = []
	var comp: RecordingComponent = _recording("comp", entries)

	var effect: GameplayEffect = Factory.infinite(
		[Factory.modifier(ATTACK, GameplayEffectModifier.Operation.DIVIDE, 0.0)]
	)
	effect.components = [comp]

	var applied: ActiveGameplayEffect = Factory.apply(target.asc, effect, source.owner)

	assert_null(applied, "division by zero refuses the whole evaluation")
	assert_true(entries.has("comp:discard"), "prepared state was discarded after the evaluator refused")


func test_an_invalid_component_rejects_the_definition_before_can_apply_ever_runs() -> void:
	var comp: RecordingComponent = _recording("comp", [])
	comp.validation_invalid = true

	var effect: GameplayEffect = Factory.infinite([])
	effect.components = [comp]

	var applied: ActiveGameplayEffect = Factory.apply(target.asc, effect, source.owner)

	assert_null(applied)
	assert_eq(comp.entries, ["comp:validate"] as Array[String])
#endregion


#region Preflight atomicity
func test_can_apply_allows_when_every_component_allows() -> void:
	target.set_base(ATTACK, 10.0)
	var effect: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 5.0)])
	effect.components = [_recording("allower", [])]

	Factory.apply(target.asc, effect, source.owner)
	assert_almost_eq(target.current_of(ATTACK), 15.0, TOLERANCE)


## One shape, two preflight stages: a component denying can_apply(), and one
## rejecting prepare_application() a step later. Either must refuse the whole
## application before any mutation, tag grant, or active_effect_added signal.
class RefusalStageCase extends RefCounted:
	var deny_can_apply: bool = false
	var reject_prepare: bool = false
	var label: String = ""


func _refusal_stage_cases() -> Array[RefusalStageCase]:
	var at_can_apply: RefusalStageCase = RefusalStageCase.new()
	at_can_apply.deny_can_apply = true
	at_can_apply.label = "can_apply denies"

	var at_prepare: RefusalStageCase = RefusalStageCase.new()
	at_prepare.reject_prepare = true
	at_prepare.label = "prepare_application rejects"

	return [at_can_apply, at_prepare] as Array[RefusalStageCase]


func test_a_refusal_at_any_preflight_stage_leaves_nothing_observable(
	case: RefusalStageCase = use_parameters(_refusal_stage_cases())
) -> void:
	target.set_base(ATTACK, 10.0)
	var refuser: RecordingComponent = _recording("refuser", [])
	refuser.deny_can_apply = case.deny_can_apply
	refuser.reject_prepare = case.reject_prepare

	var effect: GameplayEffect = Factory.granting(
		Factory.infinite([Factory.add(ATTACK, 5.0)]), [&"Status.Buffed"]
	)
	effect.components.append(refuser)

	watch_signals(target.asc)
	var applied: ActiveGameplayEffect = Factory.apply(target.asc, effect, source.owner)

	assert_null(applied, case.label)
	assert_almost_eq(target.current_of(ATTACK), 10.0, TOLERANCE, case.label)
	assert_false(target.asc.has_tag(&"Status.Buffed"), case.label)
	assert_signal_not_emitted(target.asc, "active_effect_added")
	assert_false(target.asc.has_tag(&"Status.Buffed"))
	assert_signal_not_emitted(target.asc, "active_effect_added")
#endregion


#region Asset vs target tags
func test_asset_tags_are_not_granted_to_the_target() -> void:
	var asset_component: GameplayEffectAssetTagsComponent = GameplayEffectAssetTagsComponent.new()
	asset_component.asset_tags = [&"Asset.Fire"]
	var effect: GameplayEffect = Factory.infinite([])
	effect.components = [asset_component]

	Factory.apply(target.asc, effect, source.owner)
	assert_false(target.asc.has_tag(&"Asset.Fire"))


func test_target_tags_are_granted_to_the_target() -> void:
	var effect: GameplayEffect = Factory.granting(Factory.infinite([]), [&"Status.Buffed"])
	Factory.apply(target.asc, effect, source.owner)
	assert_true(target.asc.has_tag(&"Status.Buffed"))


func test_cleanup_removes_exactly_the_tags_components_granted() -> void:
	var effect: GameplayEffect = Factory.granting(Factory.infinite([]), [&"Status.Buffed"])
	Factory.apply(target.asc, effect, source.owner)
	assert_true(target.asc.has_tag(&"Status.Buffed"))

	target.asc.cleanup()
	assert_false(target.asc.has_tag(&"Status.Buffed"))
#endregion


#region Target tag requirements (F2 required/blocked, conserved via query)
func test_required_and_blocked_tags_are_conserved_via_the_query() -> void:
	target.set_base(ATTACK, 10.0)
	var effect: GameplayEffect = Factory.blocked_by(
		Factory.requiring(Factory.instant([Factory.add(ATTACK, 5.0)]), [&"Status.Vulnerable"]),
		[&"Status.Immune"]
	)

	assert_null(Factory.apply(target.asc, effect, source.owner), "missing the required tag")

	target.asc.tags.add(&"Status.Vulnerable")
	assert_not_null(Factory.apply(target.asc, effect, source.owner), "now satisfies the requirement")
	assert_almost_eq(target.base_of(ATTACK), 15.0, TOLERANCE)

	target.asc.tags.add(&"Status.Immune")
	assert_null(Factory.apply(target.asc, effect, source.owner), "now blocked")
	assert_almost_eq(target.base_of(ATTACK), 15.0, TOLERANCE, "the blocked application never landed")
#endregion


#region Chance to apply
func test_chance_zero_always_refuses() -> void:
	var chance: GameplayEffectChanceToApplyComponent = GameplayEffectChanceToApplyComponent.new()
	chance.chance = 0.0
	var effect: GameplayEffect = Factory.infinite([])
	effect.components = [chance]

	assert_null(Factory.apply(target.asc, effect, source.owner))


func test_chance_one_always_allows() -> void:
	var chance: GameplayEffectChanceToApplyComponent = GameplayEffectChanceToApplyComponent.new()
	chance.chance = 1.0
	var effect: GameplayEffect = Factory.infinite([])
	effect.components = [chance]

	assert_not_null(Factory.apply(target.asc, effect, source.owner))


## Not the engine's global random state - one RNG owned by
## GameplayEffectComponentRuntime, reachable through the same composition
## chain a test reaches everything else through. Re-seeding it makes the
## same roll happen again.
func test_chance_draws_from_the_shared_deterministic_rng() -> void:
	var chance: GameplayEffectChanceToApplyComponent = GameplayEffectChanceToApplyComponent.new()
	chance.chance = 0.5
	var effect: GameplayEffect = Factory.infinite([])
	effect.components = [chance]

	target.asc.effects.components.rng.seed = 12345
	var first: ActiveGameplayEffect = Factory.apply(target.asc, effect, source.owner)
	if first != null:
		target.asc.remove_active_effect(first)

	target.asc.effects.components.rng.seed = 12345
	var second: ActiveGameplayEffect = Factory.apply(target.asc, effect, source.owner)

	assert_eq(first != null, second != null, "the same seed reproduces the same roll")
#endregion


#region Custom requirement and UI data
func test_a_custom_requirement_can_refuse_an_application() -> void:
	var custom: GameplayEffectCustomCanApplyComponent = GameplayEffectCustomCanApplyComponent.new()
	custom.requirement = AlwaysDeniesRequirement.new()
	var effect: GameplayEffect = Factory.infinite([])
	effect.components = [custom]

	assert_null(Factory.apply(target.asc, effect, source.owner))


func test_ui_data_never_affects_runtime_behaviour() -> void:
	target.set_base(ATTACK, 10.0)
	var ui: GameplayEffectUIDataComponent = GameplayEffectUIDataComponent.new()
	ui.display_name = "Test Buff"
	var effect: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 5.0)])
	effect.components = [ui]

	assert_not_null(Factory.apply(target.asc, effect, source.owner))
	assert_almost_eq(target.current_of(ATTACK), 15.0, TOLERANCE)
#endregion


#region Sharing a definition, never runtime state
func test_two_targets_share_one_definition_component_with_no_shared_runtime_state() -> void:
	var shared_component: GameplayEffectTargetTagsComponent = GameplayEffectTargetTagsComponent.new()
	shared_component.granted_tags = [&"Status.Buffed"]
	var effect: GameplayEffect = Factory.infinite([])
	effect.components = [shared_component]

	var target_b: ASCFixture = Fixture.create("TargetB")
	add_child_autofree(target_b.owner)

	var active_a: ActiveGameplayEffect = Factory.apply(target.asc, effect, source.owner)
	var active_b: ActiveGameplayEffect = Factory.apply(target_b.asc, effect, source.owner)

	assert_not_null(active_a)
	assert_not_null(active_b)
	assert_true(target.asc.has_tag(&"Status.Buffed"))
	assert_true(target_b.asc.has_tag(&"Status.Buffed"))

	target.asc.remove_active_effect(active_a)
	assert_false(target.asc.has_tag(&"Status.Buffed"), "removing A's grant does not touch B")
	assert_true(target_b.asc.has_tag(&"Status.Buffed"), "B's own grant is untouched")
#endregion
