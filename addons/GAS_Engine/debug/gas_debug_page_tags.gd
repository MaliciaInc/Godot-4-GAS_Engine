## Every tag the entity holds, with both of its counts.
##
## How many effects grant this exact tag, and how much of the family is held.
## They are two questions and a debugger showing one of them is a debugger
## somebody does arithmetic in front of: `State` reading nothing while
## `State.Stunned` reads two is a person working out the hierarchy by hand.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasDebugPageTags extends GasDebugPage

const TITLE: String = "Tags"

## What a tag nothing holds directly is called: a parent that exists only
## because something under it does.
const THROUGH_CHILDREN: String = "through children"
const HELD: String = "held"


func title() -> String:
	return TITLE


func columns() -> PackedStringArray:
	return PackedStringArray(["Tag", "Count", "Family", "How"])


func rows(snapshot: GasRuntimeSnapshot) -> Array[GasDebugPage.Row]:
	var drawn: Array[GasDebugPage.Row] = []
	if snapshot == null:
		return drawn
	for tag: GasRuntimeSnapshot.Tag in snapshot.tags:
		drawn.append(GasDebugPage.row_of(
			[
				tag.name,
				str(tag.count),
				str(tag.family_count),
				THROUGH_CHILDREN if tag.is_a_family_only() else HELD,
			],
			tag.is_a_family_only()
		))
	return drawn
