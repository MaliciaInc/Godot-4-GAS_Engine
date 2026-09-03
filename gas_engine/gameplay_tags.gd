## The project's gameplay tags.
##
## Written by GAS_Engine and read back by it, and safe to edit by hand: this
## file is the registry rather than a copy of one, so there is nothing for it
## to fall out of step with. A constant's value is the tag; its name is there
## so code can reach the tag without spelling the string.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0

@tool
class_name GameplayTags

const Example_Ability_Arrow_Impact: StringName = &"Example.Ability.Arrow.Impact"
const Example_Ability_Arrow_Shoot: StringName = &"Example.Ability.Arrow.Shoot"
const Example_Ability_Heal_Triggered: StringName = &"Example.Ability.Heal.Triggered"
const Example_Ability_Poison_Applied: StringName = &"Example.Ability.Poison.Applied"
const Example_Ability_Poison_Cast: StringName = &"Example.Ability.Poison.Cast"
const Example_Event_Damage_Critical: StringName = &"Example.Event.Damage.Critical"
const Example_Event_Damage_Missed: StringName = &"Example.Event.Damage.Missed"
const Example_Event_Damage_Normal: StringName = &"Example.Event.Damage.Normal"
const Example_Event_Defend_Hit: StringName = &"Example.Event.Defend.Hit"
const Example_State_Cooldown_Arrow: StringName = &"Example.State.Cooldown.Arrow"
const Example_State_Cooldown_Poison: StringName = &"Example.State.Cooldown.Poison"
