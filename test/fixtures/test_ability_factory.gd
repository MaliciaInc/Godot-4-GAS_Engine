## The one way tests grant an ability, now that an ASC never adopts an
## already-instantiated Node: pack a configured instance into a scene, give
## it through the real grant pipeline, and hand back the spec.
##
## Configure `@export` fields - ability_tag, costs, cooldown_effect,
## trigger_event_tag, and so on - on the instance BEFORE calling this: those
## survive packing because they are this ability's real authoring surface.
## Test-only tracking fields that are not exported - ProbeAbility's
## `activations`, `commits`, `channels` - do not, and are set afterward
## directly on `spec.per_actor_instance`, which is the same rule a real
## GameplayAbility subclass follows: configuration lives in the scene,
## observation happens on the running Node.
##
## @meta_license: MIT
class_name TestAbilityFactory extends RefCounted


## Give `ability` to `asc` and return the resulting spec. Null on a failed
## grant, which a caller building a scene by hand should never see: packing a
## Node this factory itself instantiated cannot produce a scene whose root is
## not a GameplayAbility.
static func give(
	asc: AbilitySystemComponent,
	ability: GameplayAbility,
	level: float = 1.0,
	input_id: int = -1,
	source: GameplayAbilitySource = null
) -> GameplayAbilitySpec:
	var scene: PackedScene = PackedScene.new()
	var pack_error: Error = scene.pack(ability)
	assert(pack_error == OK, "TestAbilityFactory: packing a fixture ability failed")
	# Packing captures state into the scene; it does not consume the Node that
	# supplied it. The grant pipeline instantiates its own copy from `scene`,
	# so this template is never added to a tree and nothing else frees it -
	# left alive, every call here orphaned one Node for the run to report.
	ability.free()
	var handle: GameplayAbilityHandle = asc.give_ability(scene, level, input_id, source)
	return asc.ability_runtime.get_spec(handle)
