## What an ability scene says about the network, read without instantiating one.
##
## The four network fields are authored on the ability and frozen into its
## snapshot at grant time, but the authority is often asked about a definition
## it has no grant of and may never run - a request naming an ability this
## character was never given, an input for one that has not been activated yet.
## So the answer comes off the packed scene's own state, and instantiating an
## ability to ask what it allows would be building a Node per message.
##
## Its own class rather than a handful of methods on the network runtime,
## because two collaborators ask these questions and neither of them should
## have to know that the answer lives in node zero's property list.
##
## Every door answers something harmless for a resource that is not an ability
## scene: an effect has no network policy, and asking one for it should get the
## default rather than fail.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetAbilityPolicy extends RefCounted


## Where and when this ability runs.
static func execution_of(definition: Resource) -> GameplayAbility.NetExecutionPolicy:
	var authored: GameplayAbility.NetExecutionPolicy = _authored(
		definition,
		GameplayAbility.NET_EXECUTION_POLICY_FIELD,
		GameplayAbility.NetExecutionPolicy.LOCAL_ONLY
	)
	return authored


## What the authority acts on when somebody else asks for it.
##
## A different question from the one above and never a translation of it: an
## ability the server alone executes can still be one whose owner is entitled
## to ask for it.
static func security_of(definition: Resource) -> GameplayAbility.NetSecurityPolicy:
	var authored: GameplayAbility.NetSecurityPolicy = _authored(
		definition,
		GameplayAbility.NET_SECURITY_POLICY_FIELD,
		GameplayAbility.NetSecurityPolicy.CLIENT_OR_SERVER
	)
	return authored


## Whether the authority honours a remote request to call this off.
static func respects_remote_cancellation(definition: Resource) -> bool:
	return _authored(definition, GameplayAbility.REMOTE_CANCELLATION_FIELD, false) == true


## Whether the input crosses rather than the activation it would cause.
static func replicates_input_directly(definition: Resource) -> bool:
	return _authored(definition, GameplayAbility.REPLICATE_INPUT_FIELD, false) == true


static func _authored(definition: Resource, field: StringName, fallback: Variant) -> Variant:
	var scene: PackedScene = definition as PackedScene
	if scene == null:
		return fallback
	var state: SceneState = scene.get_state()
	if state.get_node_count() == 0:
		return fallback
	for index: int in state.get_node_property_count(0):
		if state.get_node_property_name(0, index) == field:
			return state.get_node_property_value(0, index)
	return fallback
