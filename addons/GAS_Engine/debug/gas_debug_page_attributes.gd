## What every attribute is, what it is right now, and what last moved it.
##
## Base and current side by side because the gap between them is the question:
## a character whose base health is 100 and current health is 40 has something
## applied, and a character whose two numbers agree has nothing. The last change
## is there because "why is it 40" is never answered by the number 40.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasDebugPageAttributes extends GasDebugPage

const TITLE: String = "Attributes"
const NEVER_CHANGED: String = "-"


func title() -> String:
	return TITLE


func columns() -> PackedStringArray:
	return PackedStringArray(["Attribute", "Base", "Current", "Last change"])


func rows(snapshot: GasRuntimeSnapshot) -> Array[GasDebugPage.Row]:
	var drawn: Array[GasDebugPage.Row] = []
	if snapshot == null:
		return drawn
	for attribute: GasRuntimeSnapshot.Attribute in snapshot.attributes:
		drawn.append(GasDebugPage.row_of(
			[
				attribute.name,
				GasDebugPage.number(attribute.base),
				GasDebugPage.number(attribute.current),
				_last_change_to(snapshot, StringName(attribute.name)),
			],
			# Modified is the notable state: it is what something did to this
			# character, and it is what stops being true when the effect ends.
			not is_equal_approx(attribute.base, attribute.current)
		))
	return drawn


## What most recently moved this attribute, as a signed amount.
##
## Signed rather than "from 50 to 40", because the amount is what an author
## compares against the modifier they wrote, and the two numbers around it are
## already in the row.
static func _last_change_to(
	snapshot: GasRuntimeSnapshot, attribute_name: StringName
) -> String:
	for change: GasAttributeHistory.Change in snapshot.changes:
		if change.attribute_name != attribute_name:
			continue
		var amount: float = change.delta()
		return ("+" if amount >= 0.0 else "") + GasDebugPage.number(amount)
	return NEVER_CHANGED
