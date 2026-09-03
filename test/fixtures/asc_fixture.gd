## Builds an entity shaped the way production is.
##
##     Entity (Node)
##     `-- AbilitySystemComponent
##
## Never an orphan ASC. The ASC calls `get_parent()` to find the node cues and
## effects act on, so a parentless component behaves differently from every real
## one and a suite built on it would prove nothing about the game.
##
## Source and target are separate owners, so a test cannot accidentally pass
## because both sides were the same node.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name ASCFixture extends RefCounted

const AttributeSetScript = preload("res://test/fixtures/test_attribute_set.gd")

var owner: Node = null
var asc: AbilitySystemComponent = null
var attributes: TestAttributeSet = null


## Build an entity and its ASC. The caller adds `owner` to the tree.
##
## The set is created here rather than authored as a Resource so each fixture
## gets its own instance; a shared Resource would let one test's damage show up
## in the next. `attribute_set_script` lets a suite that needs to observe a
## TestAttributeSet hook (e.g. recording pre/post_gameplay_effect_execute
## calls) supply its own subclass instead - null keeps the plain default.
static func create(entity_name: String = "Entity", attribute_set_script: GDScript = null) -> ASCFixture:
	var fixture: ASCFixture = ASCFixture.new()

	fixture.owner = Node.new()
	fixture.owner.name = entity_name

	var set_script: GDScript = attribute_set_script if attribute_set_script != null else AttributeSetScript
	fixture.attributes = set_script.new()

	fixture.asc = AbilitySystemComponent.new()
	fixture.asc.name = String(AbilitySystemLocator.ASC_CHILD_NAME)
	fixture.asc.attribute_sets = [fixture.attributes]
	# Sharing is off by default, and the component would then work on a deep
	# copy, leaving `fixture.attributes` pointing at a set nothing reads. The
	# fixture owns one instance and hands the same one over.
	fixture.asc.share_attributes = true

	fixture.owner.add_child(fixture.asc)
	return fixture


#region Reading
func base_of(attribute_name: StringName) -> float:
	return asc.get_attribute_base(attribute_name)


func current_of(attribute_name: StringName) -> float:
	return asc.get_attribute_current(attribute_name)


## Set a base value directly, for arranging a test's starting state.
func set_base(attribute_name: StringName, value: float) -> void:
	asc.set_attribute_base(attribute_name, value)
#endregion


#region Teardown
## Free the entity and everything under it.
##
## `cleanup()` runs first so active effects release their tags and contributions
## through the normal path, rather than being dropped with the node.
func destroy() -> void:
	if asc != null and is_instance_valid(asc):
		asc.cleanup()
	if owner != null and is_instance_valid(owner):
		owner.free()
	owner = null
	asc = null
	attributes = null
#endregion
