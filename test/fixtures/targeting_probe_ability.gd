## A whole ability, written the way a real one would be.
##
## The unit suites prove each piece in isolation, which is exactly what they
## cannot prove: that the pieces fit. This one activates, pays, waits for
## someone to hand it targets, fires an effect at them, waits for confirmation
## that the hit landed, and only then reports success - suspending twice on the
## way, which is where every ownership mistake in a task runtime shows up.
##
## It records how far it got rather than only whether it finished, because a
## cast cancelled halfway and a cast that ran to the end both leave `is_active`
## false and a test that only asked that would pass either way.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name TargetingProbeAbility extends GameplayAbility

## The effect fired at whatever targets arrive.
var payload: GameplayEffect = null

## The event whose arrival means the hit was confirmed.
var confirmation_tag: StringName = &""

var commit_result: AbilityCommitResult = null
var application: GameplayTargetApplicationResult = null

## How far the activation actually got.
var reached_targets: bool = false
var reached_confirmation: bool = false
var finished_successfully: bool = false


static func build(tag: StringName) -> TargetingProbeAbility:
	var probe: TargetingProbeAbility = TargetingProbeAbility.new()
	probe.name = String(tag).replace(".", "_")
	probe.ability_tags = [tag]
	return probe


func _activate_ability() -> bool:
	commit_result = commit_ability()
	if not commit_result.is_ok():
		return false

	var targets: AbilityTaskWaitTargetData = wait_target_data()
	if targets == null:
		return false
	await targets.finished
	# A cancelled wait must not be read as an answer. The task's own state is
	# the single place that already decided, so it is asked rather than
	# inferred from whatever `finished` carried.
	if targets.state != GameplayAbilityTask.State.SUCCEEDED:
		return false
	reached_targets = true

	application = apply_effect_to_targets(payload, targets.target_data)

	var confirmation: AbilityTaskWaitGameplayEvent = wait_gameplay_event(confirmation_tag)
	if confirmation == null:
		return false
	await confirmation.finished
	if confirmation.state != GameplayAbilityTask.State.SUCCEEDED:
		return false

	reached_confirmation = true
	finished_successfully = true
	return true
