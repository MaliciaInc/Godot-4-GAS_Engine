## A name for every reason an activation can be refused.
##
## The enum is what code switches on and it is not going anywhere. This is for
## everything that is not code: a message, an icon, a sound, a tutorial that
## fires the first time somebody is refused for cost. Mapping an enum value to
## those means every project writing the same switch, and getting it wrong the
## day a reason is added.
##
## The defaults are here rather than in a project setting so the mapping is
## total by construction: a reason with no tag would be a refusal a UI could
## not describe, and the test that walks the enum is what keeps it total. A
## project overrides individual entries through its own settings.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityFailureTags extends RefCounted

const Settings = preload("res://addons/GAS_Engine/utilities/project_settings.gd")

## One tag per reason, in the enum's own order.
const DEFAULTS: Dictionary[int, StringName] = {
	AbilityRuntime.ActivationError.NONE: &"Ability.Failed.None",
	AbilityRuntime.ActivationError.ALREADY_ACTIVE: &"Ability.Failed.AlreadyActive",
	AbilityRuntime.ActivationError.ON_COOLDOWN: &"Ability.Failed.Cooldown",
	AbilityRuntime.ActivationError.BLOCKED_TAG: &"Ability.Failed.BlockedTags",
	AbilityRuntime.ActivationError.MISSING_TAG: &"Ability.Failed.MissingTags",
	AbilityRuntime.ActivationError.INSUFFICIENT_RESOURCES: &"Ability.Failed.Cost",
	AbilityRuntime.ActivationError.INTERNAL_ERROR: &"Ability.Failed.Internal",
	AbilityRuntime.ActivationError.PENDING_REMOVAL: &"Ability.Failed.PendingRemoval",
	AbilityRuntime.ActivationError.BLOCKED_BY_ACTIVE_ABILITY: &"Ability.Failed.BlockedByAbility",
	AbilityRuntime.ActivationError.BLOCKED_EXTERNALLY: &"Ability.Failed.BlockedExternally",
}


## The tag for a reason: whatever the project said, or the default.
static func of(error: AbilityRuntime.ActivationError) -> StringName:
	var setting: String = "%s/%d" % [Settings.PROJECT_SETTINGS_NAME_FAILURE_TAGS, error]
	if ProjectSettings.has_setting(setting):
		return StringName(str(ProjectSettings.get_setting(setting)))
	return DEFAULTS.get(error, &"Ability.Failed.Unknown")
