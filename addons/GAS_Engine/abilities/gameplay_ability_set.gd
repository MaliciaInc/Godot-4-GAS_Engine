## A loadout: the abilities, effects and attribute sets one thing grants.
##
## Granting a kit one call at a time is how a kit ends up half granted - an
## ability given, an effect applied, and then a failure nobody unwinds. This
## publishes as a transaction and hands back the receipt, so taking it off is one
## call rather than an inventory the game has to keep itself.
##
## The order is fixed and it is not arbitrary: attribute sets first, because an
## effect or an ability may read an attribute that does not exist until one is
## adopted; then effects, which may grant abilities of their own; then the
## abilities this set names. Retirement is the exact reverse of what was
## actually published, which is what the receipt is for.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilitySet extends Resource

@export var abilities: Array[GameplayAbilitySetEntry] = []
@export var effects: Array[GameplayEffect] = []
@export var attribute_sets: Array[AttributeSet] = []


## Put the whole thing on, or none of it.
##
## Everything is validated before anything is published, and every publication is
## recorded the moment it succeeds - so a failure half way has an exact inverse
## rather than a best guess.
##
## On a component attached to a network, only the authority may grant: a client
## that granted locally to predict a loadout would be inventing state the
## authority never agreed to, and there is no way to reconcile that.
func grant(
	asc: AbilitySystemComponent, level_multiplier: float = 1.0
) -> GameplayAbilitySetHandles:
	var receipt: GameplayAbilitySetHandles = GameplayAbilitySetHandles.new()
	if asc == null or not is_instance_valid(asc):
		return receipt
	receipt.owner_asc = asc

	if not _may_publish(asc):
		return receipt
	if not _is_well_formed():
		return receipt

	for authored: AttributeSet in attribute_sets:
		var registered: RegisteredAttributeSetHandle = asc.register_attribute_set(authored)
		if registered == null or not registered.is_valid():
			receipt.take_back()
			return receipt
		receipt.published(GameplayAbilitySetHandles.Kind.ATTRIBUTE_SET, registered)

	for effect: GameplayEffect in effects:
		var applied: ActiveGameplayEffect = asc.apply_gameplay_effect(
			effect, asc, level_multiplier
		)
		if applied == null:
			receipt.take_back()
			return receipt
		receipt.published(GameplayAbilitySetHandles.Kind.EFFECT, applied.handle)

	for entry: GameplayAbilitySetEntry in abilities:
		var handle: GameplayAbilityHandle = asc.give_ability(
			entry.ability_scene, entry.level * level_multiplier, entry.input_id
		)
		if handle == null or not handle.is_valid():
			receipt.take_back()
			return receipt
		receipt.published(GameplayAbilitySetHandles.Kind.ABILITY, handle)

	return receipt


## Whether this component is allowed to publish a loadout at all.
##
## Without a network runtime, everything is the authority and this is always
## true - which is what a single-player game is.
static func _may_publish(asc: AbilitySystemComponent) -> bool:
	if asc.network == null:
		return true
	if asc.network.is_authority():
		return true
	push_warning(
		"GAS_Engine: a loadout was granted on a client. Only the authority grants; "
		+ "the client is told what it has."
	)
	return false


## Whether every entry names something. Asked before anything is published,
## because half a kit is worse than none of it.
func _is_well_formed() -> bool:
	for entry: GameplayAbilitySetEntry in abilities:
		if entry == null or entry.ability_scene == null:
			push_error("GAS_Engine: an ability set entry names no scene.")
			return false
	for effect: GameplayEffect in effects:
		if effect == null:
			push_error("GAS_Engine: an ability set names an empty effect.")
			return false
	for authored: AttributeSet in attribute_sets:
		if authored == null:
			push_error("GAS_Engine: an ability set names an empty attribute set.")
			return false
	return true
