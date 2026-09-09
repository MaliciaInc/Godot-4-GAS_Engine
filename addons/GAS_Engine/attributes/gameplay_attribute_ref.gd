## Which attribute, said in a way that cannot mean two of them.
##
## An attribute has only ever been named by a bare `health`, and that is fine
## right up to the moment an entity carries two sets that both declare one - a
## character sheet and a vehicle, a body and a shield. From then on the bare
## name has two answers and the engine picks whichever set it walked into first,
## silently, differently on a different day.
##
## The set is what removes the ambiguity, and it is optional on purpose: naming
## it is only necessary where the name is actually shared, and demanding it
## everywhere would rewrite every effect anybody has already authored.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAttributeRef extends Resource

@export var set_name: StringName = &""
@export var attribute_name: StringName = &""

func is_valid() -> bool:
	return attribute_name != &""

## The reference to use for a field that may have been authored either way.
##
## The typed one wins where somebody wrote it, and a bare name is wrapped into
## the same shape so that everything downstream asks one question. Nothing has
## to migrate: an effect authored before this reads exactly as it did.
static func resolved(
	authored: GameplayAttributeRef, legacy: StringName
) -> GameplayAttributeRef:
	if authored != null and authored.is_valid():
		return authored
	var made: GameplayAttributeRef = GameplayAttributeRef.new()
	made.attribute_name = legacy
	return made


func equals(other: GameplayAttributeRef) -> bool:
	return (
		other != null
		and set_name == other.set_name
		and attribute_name == other.attribute_name
	)
