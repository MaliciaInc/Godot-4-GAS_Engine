## Which attribute a name means, on an entity that may carry several sets.
##
## Separate from the runtime because it is a different question. The runtime
## owns what attributes are worth - the contributions, the composition, the
## clamps, the recomposition after a write. This owns only which one is being
## talked about, and it needs nothing but the list of sets to answer.
##
## The distinction matters the moment two sets declare the same attribute. A
## character and the vehicle they are driving both have `health`, and picking
## whichever set was walked into first is an answer that changes when somebody
## reorders a list. So a name that means two things is refused, and a name that
## says which set it meant is answered exactly.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAttributeLookup extends RefCounted


## The name a set answers to.
##
## Its class, which is what an author writes when they say which set they meant.
## A set given a `resource_name` of its own answers to that instead: two
## vehicles on one entity are the same class and are not the same set.
static func name_of(attribute_set: AttributeSet) -> StringName:
	if attribute_set == null:
		return &""
	if attribute_set.resource_name != "":
		return StringName(attribute_set.resource_name)
	var script: Script = attribute_set.get_script()
	return script.get_global_name() if script != null else &""


## Whether more than one of those sets declares that attribute.
static func is_ambiguous(sets: Array[AttributeSet], attribute_name: StringName) -> bool:
	var found: int = 0
	for attribute_set: AttributeSet in sets:
		if attribute_set != null and attribute_set.attribute_named(attribute_name) != null:
			found += 1
			if found > 1:
				return true
	return false


## The set a reference names, or null when nothing answers to it.
##
## A reference that names its set is answered exactly. One that does not is
## answered the way a bare name always was - and only while that is not
## ambiguous, because the alternative is choosing on the author's behalf and
## being wrong half the time, silently.
static func set_for(
	sets: Array[AttributeSet], reference: GameplayAttributeRef
) -> AttributeSet:
	if reference == null or not reference.is_valid():
		return null

	if reference.set_name == &"":
		if is_ambiguous(sets, reference.attribute_name):
			return null
		return _first_declaring(sets, reference.attribute_name)

	for attribute_set: AttributeSet in sets:
		if attribute_set == null or name_of(attribute_set) != reference.set_name:
			continue
		if attribute_set.attribute_named(reference.attribute_name) != null:
			return attribute_set
	return null


## The attribute a reference names, or null.
static func attribute_for(
	sets: Array[AttributeSet], reference: GameplayAttributeRef
) -> AttributeData:
	var attribute_set: AttributeSet = set_for(sets, reference)
	if attribute_set == null:
		return null
	return attribute_set.attribute_named(reference.attribute_name)


static func _first_declaring(
	sets: Array[AttributeSet], attribute_name: StringName
) -> AttributeSet:
	for attribute_set: AttributeSet in sets:
		if attribute_set != null and attribute_set.attribute_named(attribute_name) != null:
			return attribute_set
	return null
