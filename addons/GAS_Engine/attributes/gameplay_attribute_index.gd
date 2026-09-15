## Which set on one entity declares which attribute.
##
## Read when the sets change and consulted everywhere else. Asked of every set's
## property list on each recomposition instead, it was measured at 27 of the
## 100 microseconds a recomposition of six attributes took - and applying one
## effect recomposes up to three times.
##
## A set is read when it arrives. One that starts declaring a different list of
## attributes afterwards is a set to release and adopt again, which is the same
## thing a game does to put a kit on or take one off.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAttributeIndex extends RefCounted


var _sets: Array[AttributeSet] = []

## Every attribute name across every set, in set order and each once; the set
## that declares each one first; and the names met more than once.
var _names: Array[StringName] = []
var _declaring: Dictionary[StringName, AttributeSet] = {}
var _declared_twice: Dictionary[StringName, bool] = {}


## Hold these sets instead of whatever was held, and read them.
func hold(taken: Array[AttributeSet]) -> void:
	_sets = taken
	_read()


## Hold one more set, after the others.
func adopt(taken: AttributeSet) -> void:
	_sets.append(taken)
	_read()


## Stop holding one set. False when it was not held.
func release(taken: AttributeSet) -> bool:
	if taken == null or not _sets.has(taken):
		return false
	_sets.erase(taken)
	_read()
	return true


## The sets held, in the order they were handed over, nulls in their places.
##
## For reading. A set appended to this list is a set nobody read, and every
## lookup by name would go on answering as if it were not there.
func held() -> Array[AttributeSet]:
	return _sets


## Every name met when the sets were read, in set order.
##
## One whose property was emptied since is still listed: `declaring` is what
## says whether anything still answers to it, and a pass that asks that of every
## name anyway has no reason to ask it twice.
func listed() -> Array[StringName]:
	return _names


## Every name some set still declares, in set order.
func names() -> Array[StringName]:
	var declared: Array[StringName] = []
	for name: StringName in _names:
		if declaring(name) != null:
			declared.append(name)
	return declared


## The set that declares an attribute, or null.
##
## Answered from the index and confirmed against the set itself. A property that
## held an attribute when its set arrived and was emptied since is not an
## attribute any more, and the next set declaring the name is the one that
## answers - which is what walking every set always said.
func declaring(attribute_name: StringName) -> AttributeSet:
	var declared: AttributeSet = _declaring.get(attribute_name)
	if declared == null:
		return null
	if declared.attribute_named(attribute_name) != null:
		return declared
	return GameplayAttributeLookup.first_declaring(_sets, attribute_name)


## Whether more than one set declares that attribute.
##
## Only a name met twice when the sets were read can mean two attributes now, so
## the walk that confirms it is made for those names and for no others.
func is_ambiguous(attribute_name: StringName) -> bool:
	if not _declared_twice.has(attribute_name):
		return false
	return GameplayAttributeLookup.is_ambiguous(_sets, attribute_name)


func _read() -> void:
	_names.clear()
	_declaring.clear()
	_declared_twice.clear()
	for attribute_set: AttributeSet in _sets:
		if attribute_set == null:
			continue
		for name: StringName in attribute_set.get_attribute_names():
			if _declaring.has(name):
				_declared_twice[name] = true
				continue
			_declaring[name] = attribute_set
			_names.append(name)
