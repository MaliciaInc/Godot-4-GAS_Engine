## How the slam is aimed: a preset that says what an area selects, and the
## reticle that shows it before anybody commits to it.
##
## Both are Resources the addon ships. The whole point of F6.3 is that a game
## aiming an area effect writes no targeting code: it picks a provider, gives it
## a radius, and hands the reticle the data the provider is previewing.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name SampleTargeting extends RefCounted

## How wide the slam is, and how far ahead of the caster it can be put.
const SLAM_RADIUS: float = 4.0
const SLAM_REACH: float = 12.0


## What a confirmed slam selects: everything in a circle, nearest first.
##
## Two tasks rather than one call, because the order is the answer: selecting
## and then sorting is a different list from sorting and then selecting, and a
## preset is where that order is written down instead of being implied by the
## order somebody happened to call two methods in.
static func slam_preset() -> GameplayTargetingPreset:
	var preset: GameplayTargetingPreset = GameplayTargetingPreset.new()
	preset.resource_name = "SampleSlamPreset"

	var area: TargetingSelectAoe = TargetingSelectAoe.new()
	area.radius = SLAM_RADIUS

	var nearest: TargetingSortByDistance = TargetingSortByDistance.new()

	preset.tasks = [area, nearest]
	return preset


## The provider that lets somebody put the slam somewhere before committing.
##
## A placement provider rather than a raycast: the player is choosing a spot on
## the ground, and the ability is not fired until they say so.
static func slam_provider() -> GameplayPlacementProvider3D:
	var provider: GameplayPlacementProvider3D = GameplayPlacementProvider3D.new()
	provider.max_range = SLAM_REACH
	return provider


## The ring the player sees while they are choosing.
##
## Its radius is the preset's radius, read from the same constant, because a
## preview that showed a different circle from the one that lands is worse than
## no preview at all.
static func slam_reticle() -> GameplayTargetReticle3D:
	var reticle: GameplayTargetReticle3D = GameplayTargetReticle3D.new()
	reticle.name = "SampleSlamReticle"
	reticle.set_radius(SLAM_RADIUS)
	return reticle
