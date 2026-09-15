## Every contribution standing on one entity, kept by the attribute it is about
## and by the application that added it.
##
## Composing one attribute used to walk every contribution on the entity,
## skipping the ones about something else - measured at a thousand effects on
## one character, that is six seconds, because every attribute pays for every
## other attribute's modifiers. Taking one application's contributions away
## walked all of them too, to find the few that were its own, so removing an
## effect grew with everything else standing on the character.
##
## Within one attribute the order is the order contributions were added in,
## which is the application order the algebra reads and must not move.
##
## Held by GameplayAttributeRuntime and by nothing else: what arrives here has
## already been through the validation that decides whether it may.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAttributeContributions extends RefCounted


## The value type is a bare `Array` because GDScript will not nest typed
## collections. What is stored in it is always a typed one, made below and
## read back into a typed local - so the type survives even though the
## dictionary cannot declare it.
var _by_attribute: Dictionary[StringName, Array] = {}
var _by_application: Dictionary[int, Array] = {}

## How many contributions are standing, counted as they come and go.
var _total: int = 0


func add(arriving: Array[AttributeModifierContribution]) -> void:
	for contribution: AttributeModifierContribution in arriving:
		if contribution != null:
			_about(contribution.attribute_name).append(contribution)
			_added_by(contribution.application_order).append(contribution)
			_total += 1


## Take away every contribution one application added.
func remove_of(application_order: int) -> void:
	if not _by_application.has(application_order):
		return
	var leaving: Array[AttributeModifierContribution] = _added_by(application_order)
	_by_application.erase(application_order)
	for contribution: AttributeModifierContribution in leaving:
		_about(contribution.attribute_name).erase(contribution)
	_total -= leaving.size()


func clear() -> void:
	_by_attribute.clear()
	_by_application.clear()
	_total = 0


func count() -> int:
	return _total


## One attribute's contributions, as a list the caller owns.
func copy_for(attribute_name: StringName) -> Array[AttributeModifierContribution]:
	return _about(attribute_name).duplicate()


## One attribute's contributions as they are stored, for a fold to read.
##
## Not a copy, because recomposing is the hot path and a copy per attribute per
## pass is what one would cost. Not for writing either: appending to it is
## appending past the validation every contribution goes through on the way in,
## and leaves the application that added it unable to take it away.
func standing(attribute_name: StringName) -> Array[AttributeModifierContribution]:
	return _about(attribute_name)


## One attribute's contributions with the candidates about it after them, as a
## new list - the order a preflight asks the algebra to read them in. Nothing is
## added here.
func with_candidates(
	attribute_name: StringName, candidates: Array[AttributeModifierContribution]
) -> Array[AttributeModifierContribution]:
	var combined: Array[AttributeModifierContribution] = _about(attribute_name).duplicate()
	for candidate: AttributeModifierContribution in candidates:
		if candidate != null and candidate.attribute_name == attribute_name:
			combined.append(candidate)
	return combined


## The stored list for one attribute, made empty the first time it is asked for.
func _about(attribute_name: StringName) -> Array[AttributeModifierContribution]:
	if not _by_attribute.has(attribute_name):
		var started: Array[AttributeModifierContribution] = []
		_by_attribute[attribute_name] = started
	var found: Array[AttributeModifierContribution] = _by_attribute[attribute_name]
	return found


## The stored list for one application, made the same way.
func _added_by(application_order: int) -> Array[AttributeModifierContribution]:
	if not _by_application.has(application_order):
		var started: Array[AttributeModifierContribution] = []
		_by_application[application_order] = started
	var found: Array[AttributeModifierContribution] = _by_application[application_order]
	return found
