## What was granted: a handle, the frozen definition it was granted from, and
## the runtime instance state that belongs to the grant rather than to any one
## activation.
##
## This is the registry entry `AbilityRuntime` actually keeps. A
## `GameplayAbility` Node is one running instance of it, not the grant itself
## - which is the separation this task exists to make.
##
## Phase 3 still resolves every spec to exactly one `per_actor_instance`;
## `active_instances` and the counters below exist now so Task 5's
## PER_EXECUTION policy has somewhere to land without another spec-shaped
## type appearing later.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayAbilitySpec extends RefCounted

var handle: GameplayAbilityHandle = null
var definition: GameplayAbilityDefinitionSnapshot = null
var level: float = 1.0
var input_id: int = -1
var source: GameplayAbilitySource = null
var dynamic_tags: Array[StringName] = []

var active_count: int = 0
var remove_after_activation: bool = false
var activate_once: bool = false
var pending_remove: bool = false

## Phase 3's one instance. Always this ability's PER_ACTOR Node, parented
## under the owning ASC.
var per_actor_instance: GameplayAbility = null

## Empty in Phase 3. Reserved for PER_EXECUTION.
var active_instances: Array[GameplayAbility] = []
