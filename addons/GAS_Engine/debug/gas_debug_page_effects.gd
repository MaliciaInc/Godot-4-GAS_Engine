## Every effect on the entity, how long it has left, and whether it is actually
## doing anything.
##
## Inhibited is the column this page exists for. An effect that is applied but
## not in force looks exactly like one that is working, and the state somebody
## stares at longest is the stun they can see in the list that is not stunning
## anybody.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasDebugPageEffects extends GasDebugPage

const TITLE: String = "Active effects"

## What the state column says, in the words the rest of this reads in: an
## effect is in force or it is not, which is the distinction the column exists
## for. "active" would be the word, and it is already the wire's name for how
## many activations an ability has - one word for two things is how somebody
## reads the wrong one.
const IN_FORCE: String = "in force"
const INHIBITED: String = "not in force"


func title() -> String:
	return TITLE


## Not the title lowered, which is two words. The one the wire already uses for
## this part of an entity, so a person reading a log and a person typing a
## command are saying the same thing.
func command() -> String:
	return GasDebugMessage.EFFECTS


func columns() -> PackedStringArray:
	return PackedStringArray(["Effect", "Stacks", "Seconds", "Turns", "State"])


func rows(snapshot: GasRuntimeSnapshot) -> Array[GasDebugPage.Row]:
	var drawn: Array[GasDebugPage.Row] = []
	if snapshot == null:
		return drawn
	for effect: GasRuntimeSnapshot.Effect in snapshot.effects:
		drawn.append(GasDebugPage.row_of(
			[
				effect.name,
				str(effect.stacks),
				GasDebugPage.seconds(effect.seconds_left),
				GasDebugPage.turns(effect.turns_left),
				INHIBITED if effect.inhibited else IN_FORCE,
			],
			effect.inhibited
		))
	return drawn
