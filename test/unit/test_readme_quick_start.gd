## The README's quick start, executed.
##
## A getting-started guide is the one part of a framework that is read before
## anything else and verified by nobody: it is prose, it sits beside the code
## rather than inside it, and it goes quietly wrong the first time a method is
## renamed. This suite already exists to stop a declared authority drifting
## from the tree, and a README is a declared authority.
##
## So the printed steps are built here the way a reader would build them - a
## node with a component under it, an ability packed into a scene, granted, and
## activated - and the arithmetic the README promises is asserted. If the quick
## start stops working, this stops passing.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const README: String = "res://README.md"

## What the README tells a reader to call the component's node. It is not
## decoration: the component finds the thing it acts on by asking its parent,
## and everything else finds the component by this name.
const CHILD_NAME: String = "AbilitySystemComponent"

const ENEMIES: StringName = &"enemies"
const FULL: float = 100.0
const AFTER_ONE_FIREBALL: float = 70.0


#region The quick start itself
## Step 4 of the README, verbatim in shape: build a character, grant the
## ability, fire it.
func _character(called: String) -> AbilitySystemComponent:
	var body: Node = Node.new()
	body.name = called

	var asc: AbilitySystemComponent = AbilitySystemComponent.new()
	asc.name = CHILD_NAME
	asc.attribute_sets = [QuickStartAttributes.new()] as Array[AttributeSet]
	body.add_child(asc)

	add_child_autofree(body)
	return asc


## Packing captures the ability's authored numbers into a scene; it does not
## consume the Node that supplied them, so the template is freed here rather
## than left to be reported as an orphan.
func _packed(ability: GameplayAbility) -> PackedScene:
	var scene: PackedScene = PackedScene.new()
	assert_eq(scene.pack(ability), OK, "the ability packs into a scene")
	ability.free()
	return scene


func test_the_printed_quick_start_takes_a_target_from_100_to_70() -> void:
	var hero: AbilitySystemComponent = _character("Hero")
	var goblin: AbilitySystemComponent = _character("Goblin")
	goblin.get_parent().add_to_group(ENEMIES)

	assert_eq(goblin.get_attribute_current(QuickStartAttributes.HEALTH), FULL, "full to start")

	var handle: GameplayAbilityHandle = hero.give_ability(_packed(QuickStartFireball.new()))
	assert_true(handle.is_valid(), "the ability was granted")

	var fired: GameplayAbilityActivationResult = hero.ability_runtime.try_activate(handle)
	assert_true(fired.is_ok(), "and it activated: %s" % fired.status)

	assert_eq(
		goblin.get_attribute_current(QuickStartAttributes.HEALTH),
		AFTER_ONE_FIREBALL,
		"the number the README promises"
	)


## Aimed, not broadcast. A fireball that also burned its caster would still
## have passed the assertion above.
func test_the_caster_is_not_its_own_target() -> void:
	var hero: AbilitySystemComponent = _character("Hero")
	var goblin: AbilitySystemComponent = _character("Goblin")
	goblin.get_parent().add_to_group(ENEMIES)

	var handle: GameplayAbilityHandle = hero.give_ability(_packed(QuickStartFireball.new()))
	hero.ability_runtime.try_activate(handle)

	assert_eq(
		hero.get_attribute_current(QuickStartAttributes.HEALTH), FULL, "the caster is untouched"
	)


## Two characters, two health pools. This is the `_init()` block the README
## calls the most common first mistake: without it both sets share one
## AttributeData and damage to either shows up on both.
func test_two_characters_do_not_share_one_health_pool() -> void:
	var hero: AbilitySystemComponent = _character("Hero")
	var goblin: AbilitySystemComponent = _character("Goblin")

	goblin.set_attribute_base(QuickStartAttributes.HEALTH, 40.0)

	assert_eq(goblin.get_attribute_current(QuickStartAttributes.HEALTH), 40.0, "one moved")
	assert_eq(hero.get_attribute_current(QuickStartAttributes.HEALTH), FULL, "the other did not")
#endregion


#region Against the file, not against memory
## Every line the README asks a reader to type is a line this suite ran.
##
## The fixtures above are what executes; the README is what a person copies.
## Checking the load-bearing lines appear in both is what stops the two from
## parting company - a renamed method would otherwise leave the suite green and
## the guide wrong, which is the exact failure this project keeps closing.
const MUST_APPEAR: Array[String] = [
	"asc.name = \"AbilitySystemComponent\"",
	"asc.give_ability(FIREBALL)",
	"asc.ability_runtime.try_activate(handle)",
	"if not commit_ability().is_ok():",
	"apply_effect_to_targets(_payload(), struck)",
	"effect.policy = GameplayEffect.DurationPolicy.INSTANT",
	"modifier.operation = GameplayEffectModifier.Operation.ADD",
	"AbilitySystemLocator.find_for_node(enemy)",
	"func pre_attribute_base_change(",
	"func _init() -> void:",
]


func test_the_readme_still_prints_the_calls_that_were_run() -> void:
	var printed: String = FileAccess.get_file_as_string(README)

	assert_false(printed.is_empty(), "the README is where it is expected to be")
	for line: String in MUST_APPEAR:
		assert_true(printed.contains(line), "the quick start still prints `%s`" % line)
#endregion
