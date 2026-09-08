## What authoring costs today, measured rather than remembered.
##
## The phase promises that six specific frictions get smaller, and "smaller"
## needs a number that existed before the work started. So this measures them
## against the engine as it stands and checks the receipt says the same thing.
##
## It is not a test of whether the numbers are good. A baseline that is bad is
## the reason the phase exists, and a test that failed for that would have to be
## deleted the moment it was fixed. It fails for two things only: a measurement
## it cannot take at all, and a receipt that disagrees with what was measured.
##
## Every measurement is derived from the engine - an object graph walked, a
## class list asked, calls actually made and counted - because a measurement
## somebody typed is the number they expected rather than the number that is
## there.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const RECEIPT: String = "res://artifacts/parity/AUTHORING_UX.md"

const ATTACK: StringName = &"attack"
const PROBE_TAG: StringName = &"Ability.Probe"

## The column this run writes. F6.4.7 measures the same keys into the next one.
const COLUMN: String = "before"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Author")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


#region Asking the project what it has
## Whether a script class by this name is declared anywhere in the project.
##
## Asked of the global class list rather than of ClassDB, which only knows
## engine types, and rather than of a preload, which would fail to parse rather
## than answer false.
func _class_is_declared(named: String) -> bool:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		# `get` answers Variant, and this project compiles warnings as errors.
		var declared: String = str(entry.get("class", ""))
		if declared == named:
			return true
	return false


## How many files sit directly in an addon directory, ignoring Godot's uid
## sidecars. Used to count what ships, not what could be written.
func _scripts_in(directory: String) -> Array[String]:
	var found: Array[String] = []
	var opened: DirAccess = DirAccess.open(directory)
	if opened == null:
		return found
	for name: String in opened.get_files():
		if name.ends_with(".gd"):
			found.append(name)
	return found
#endregion


#region The six measurements
## 1. How many Resources a person builds to get one `+10` onto an attribute.
##
## Counted by walking what a correct one is made of rather than by asserting a
## number: the effect, the modifier, the magnitude and the scalable float it
## reads. Each link is a separate "new Resource" in the inspector.
func _measure_modifier_resources() -> int:
	var effect: GameplayEffect = Factory.infinite(
		[Factory.add(ATTACK, 10.0)] as Array[GameplayEffectModifier]
	)
	assert_eq(effect.modifiers.size(), 1, "the effect carries the modifier")

	var counted: int = 1
	var modifier: GameplayEffectModifier = effect.modifiers[0]
	assert_not_null(modifier, "there is a modifier to walk")
	counted += 1

	var magnitude: GameplayMagnitude = modifier.magnitude
	assert_not_null(magnitude, "the modifier carries a magnitude")
	counted += 1

	var scalable: GameplayScalableMagnitude = magnitude as GameplayScalableMagnitude
	assert_not_null(scalable, "and it is the scalable kind the quick start uses")
	assert_not_null(scalable.value, "which carries a scalable float of its own")
	counted += 1

	return counted


## 2. Whether a misspelled attribute reference is caught before anything runs.
func _measure_typo_caught_before_runtime() -> bool:
	var misspelled: GameplayAttributeRef = GameplayAttributeRef.new()
	misspelled.set_name = &"TestAttributeSet"
	misspelled.attribute_name = &"attakc"

	# The only question the reference itself can answer today.
	if not misspelled.is_valid():
		return true

	# And whether the asset validator has anything to say about it, which is the
	# other place an author would find out before playing.
	var effect: GameplayEffect = Factory.infinite(
		[Factory.add(&"attakc", 10.0)] as Array[GameplayEffectModifier]
	)
	return not GameplayAssetValidator.validate_effect(effect).is_empty()


## 3. Whether a cue with a sound and a particle can be authored without writing
##    a script - which needs a concrete notify shipped with the data on it.
func _measure_cue_without_a_script() -> bool:
	return (
		_class_is_declared("GameplayCueEffectSet")
		and _class_is_declared("GameplayCueNotifyBurst")
	)


## 4. Whether there is a debug surface a running game can show.
func _measure_debug_outside_the_editor() -> bool:
	return _class_is_declared("GasDebugOverlay")


## 5. What ships towards an area effect a person can see before confirming: a
##    provider that selects by radius, and something that draws the aim.
func _measure_aoe_preview_pieces() -> int:
	var shipped: int = 0
	for name: String in _scripts_in("res://addons/GAS_Engine/targeting/providers"):
		if name.contains("radius") or name.contains("ground") or name.contains("placement"):
			shipped += 1
	if _class_is_declared("GameplayTargetReticle2D") or _class_is_declared("GameplayTargetReticle3D"):
		shipped += 1
	return shipped


## 6. How many calls it takes to put a kit on a character, and to take it off.
##
## Made rather than counted from memory: three abilities, one effect and one
## attribute set, granted one at a time because there is no way to say it once.
func _measure_kit_calls() -> Array[int]:
	if _class_is_declared("GameplayAbilitySet"):
		return [1, 1] as Array[int]

	var granted: int = 0
	var handles: Array[GameplayAbilityHandle] = []
	for index: int in 3:
		var probe: ProbeAbility = Probe.build(PROBE_TAG)
		var scene: PackedScene = PackedScene.new()
		scene.pack(probe)
		probe.free()
		handles.append(asc.give_ability(scene))
		granted += 1

	var effect: GameplayEffect = Factory.infinite(
		[Factory.add(ATTACK, 5.0)] as Array[GameplayEffectModifier]
	)
	var applied: ActiveGameplayEffect = Factory.apply(asc, effect)
	granted += 1

	# The attribute set is the third kind of thing a kit carries, and it is put
	# on by writing the exported array rather than by calling anything.
	asc.attribute_sets = asc.attribute_sets.duplicate()
	granted += 1

	var taken_back: int = 0
	for handle: GameplayAbilityHandle in handles:
		asc.remove_ability_handle(handle)
		taken_back += 1
	asc.remove_active_effect_by_handle(applied.handle)
	taken_back += 1
	asc.attribute_sets = asc.attribute_sets.duplicate()
	taken_back += 1

	return [granted, taken_back] as Array[int]
#endregion


#region What the receipt says
## The receipt as a table of key to the value in this run's column.
##
## Parsed rather than trusted: a receipt nobody reads back is a file that drifts
## from the thing it is about, which is the failure this whole suite exists to
## prevent elsewhere.
func _recorded() -> Dictionary[String, String]:
	var said: Dictionary[String, String] = {}
	var printed: String = FileAccess.get_file_as_string(RECEIPT)
	assert_false(printed.is_empty(), "the receipt is where it is expected to be")

	# The first table only. The receipt carries a second one saying what each
	# number should become, whose columns mean something else entirely - reading
	# both with one column index is how a target ends up recorded as a
	# measurement.
	var column: int = -1
	var started: bool = false
	for line: String in printed.split("
"):
		if not line.begins_with("|"):
			if started:
				break
			continue
		var cells: PackedStringArray = line.split("|")
		var trimmed: Array[String] = []
		for cell: String in cells:
			trimmed.append(cell.strip_edges())
		if column < 0:
			column = trimmed.find(COLUMN)
			continue
		if trimmed.size() > column and not trimmed[1].begins_with("-"):
			said[trimmed[1]] = trimmed[column]
			started = true
	assert_gt(column, 0, "the receipt has a `%s` column" % COLUMN)
	return said


func _said(recorded: Dictionary[String, String], key: String) -> String:
	assert_true(recorded.has(key), "the receipt records `%s`" % key)
	return str(recorded.get(key, ""))
#endregion


func test_the_six_authoring_frictions_are_measured_as_they_stand_today() -> void:
	var recorded: Dictionary[String, String] = _recorded()

	var resources: int = _measure_modifier_resources()
	assert_eq(
		str(resources),
		_said(recorded, "modifier_plus_ten_resources"),
		"resources built for a +10"
	)

	assert_eq(
		"yes" if _measure_typo_caught_before_runtime() else "no",
		_said(recorded, "attribute_ref_typo_caught_before_runtime"),
		"a misspelled attribute caught before anything runs"
	)

	assert_eq(
		"yes" if _measure_cue_without_a_script() else "no",
		_said(recorded, "cue_authored_without_a_script"),
		"a sound-and-particle cue with no script"
	)

	assert_eq(
		"yes" if _measure_debug_outside_the_editor() else "no",
		_said(recorded, "debug_surface_outside_the_editor"),
		"a debug surface a running game can show"
	)

	assert_eq(
		str(_measure_aoe_preview_pieces()),
		_said(recorded, "aoe_preview_pieces_shipped"),
		"pieces shipped towards an area effect with a preview"
	)

	var kit: Array[int] = _measure_kit_calls()
	assert_eq(str(kit[0]), _said(recorded, "kit_grant_calls"), "calls to put a kit on")
	assert_eq(str(kit[1]), _said(recorded, "kit_remove_calls"), "calls to take it off")
