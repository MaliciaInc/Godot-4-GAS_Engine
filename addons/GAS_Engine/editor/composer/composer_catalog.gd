## The node vocabulary, grouped the way the palette shows it.
##
## The categories live here rather than in the panel that draws them. A view
## owning the list is a view that decides what the Composer can express, and the
## next thing to need it - search, the command palette, the writer - would each
## grow a copy.
##
## Only the groups exist so far. Their entries arrive with the catalog itself,
## and every one of them will be a call to a public engine API: there is no node
## without a line of GDScript behind it.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerCatalog extends RefCounted

const FLOW: StringName = &"Flow"
const ABILITY: StringName = &"Ability"
const TASKS: StringName = &"Tasks"
const EFFECTS: StringName = &"Effects"
const TAGS: StringName = &"Tags"
const TARGETING: StringName = &"Targeting"
const EVENTS: StringName = &"Events"
const CUES: StringName = &"Cues"
const CONTEXT: StringName = &"Context"
const VALUES: StringName = &"Values"

## In the order a person reads them: what shapes a method first, then what it
## does, then what it reads.
const GROUPS: Array[StringName] = [
	FLOW, ABILITY, TASKS, EFFECTS, TAGS, TARGETING, EVENTS, CUES, CONTEXT, VALUES,
]


## The nodes in a group. Empty until the catalog is filled.
static func entries(group: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	if not GROUPS.has(group):
		return found
	return found
