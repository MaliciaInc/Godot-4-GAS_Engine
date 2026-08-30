## An ability that records what the input routing did to it.
##
## The base class's active-input hooks are empty by design - "press again to
## cancel" and "hold to charge, release to fire" are the subclass's business -
## so a test can only see whether routing worked by subclassing and counting.
##
## @meta_license: MIT
class_name ProbeAbility extends GameplayAbility

## Emitted by the test to let a channelled activation finish.
signal channel_gate

## How many times _activate_ability actually ran.
var activations: int = 0

## Presses and releases that arrived while the ability was already running.
var presses_while_active: int = 0
var releases_while_active: int = 0

## Set false to make activation report failure, so a test can tell an ability
## that ran and failed from one that never ran.
var succeeds: bool = true

## Set true to stay active until `channel_gate` fires.
##
## try_activate closes an ability that is still active when _activate_ability
## returns, so the only way to remain active is to suspend inside it - which is
## also how a real channelled ability works.
var channels: bool = false

## Set true to pay the cost and start the cooldowns, which is what a real
## ability does the moment it is committed. Off by default so a test that
## only cares about routing does not have to arrange resources.
var commits: bool = false

## What the last commit answered. Kept rather than discarded so a test can
## see why a commit was refused, not merely that the ability did not pay.
var last_commit: AbilityCommitResult = null


static func build(tag: StringName) -> ProbeAbility:
	var probe: ProbeAbility = ProbeAbility.new()
	probe.name = String(tag).replace(".", "_")
	probe.ability_tag = tag
	return probe


func _activate_ability() -> bool:
	activations += 1
	if commits:
		last_commit = commit_ability()
	if channels:
		await channel_gate
	return succeeds


func _active_input_pressed(_asc: AbilitySystemComponent) -> void:
	presses_while_active += 1


func _active_input_released(_asc: AbilitySystemComponent) -> void:
	releases_while_active += 1
