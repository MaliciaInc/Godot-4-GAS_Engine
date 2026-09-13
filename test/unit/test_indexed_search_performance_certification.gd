## What the effect indices cost and what they saved, at the loads named below,
## on whatever machine ran it.
##
## Two kinds of number, and only one of them is a gate. The structural
## counts - how many candidates a search compared, how many effects a tag change
## reevaluated - are the same on every machine and are asserted. The times are a
## fact about this machine and nothing here fails for them: a threshold in
## milliseconds is how a suite comes to fail on somebody's laptop and be
## switched off.
##
## This suite is specified to live at `test/performance/`. It lives in
## `test/unit/` because that is the directory the headless runner runs, and its
## collection guard counts test scripts in one directory on purpose - a
## certification that never ran would certify nothing.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const RECEIPT: String = "res://artifacts/parity/PERFORMANCE_F6.md"

## The loads named below, at the sizes named for them.
const EFFECT_SCALES: Array[int] = [100, 1000, 10000]
const ABILITY_SCALES: Array[int] = [10, 100, 1000]
const TAG_LOOKUPS: int = 10000
const TAG_CHANGE_REEVALUATIONS: int = 1000
const STACK_SEARCHES: int = 1000

## Enough runs for a percentile to mean something, few enough that the largest
## load does not turn the suite into something people skip.
const WARMUP: int = 1
const RUNS: int = 5

const BURNING: StringName = &"State.Burning"
const ABILITY_TAG: StringName = &"Ability.Probe"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Certified")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


#region What is asserted
## The stack search does not grow with what is already on the character.
##
## The closing criterion stated outright: not a number on a laptop,
## but the linear growth gone. Measured at three scales two orders of magnitude
## apart - if the search were still reading the list, the count would grow with
## it.
func test_the_stack_search_does_not_grow_with_the_crowd() -> void:
	var measured: Array[int] = []
	for scale: int in EFFECT_SCALES:
		measured.append(_stack_searches_at(scale))

	for index: int in measured.size():
		assert_lt(
			measured[index], 3,
			"a search at %d compared %d" % [EFFECT_SCALES[index], measured[index]]
		)
	assert_eq(
		measured[0], measured[measured.size() - 1],
		"and a hundred-fold larger crowd compares exactly as many: %s" % [measured]
	)


## A tag change does not grow with what is already on the character either.
func test_a_tag_change_does_not_grow_with_the_crowd() -> void:
	var measured: Array[int] = []
	for scale: int in EFFECT_SCALES:
		measured.append(_reevaluations_at(scale))

	for index: int in measured.size():
		assert_eq(
			measured[index], 1,
			"a tag change at %d reevaluated %d" % [EFFECT_SCALES[index], measured[index]]
		)


## A thousand applications and removals leave the index holding nothing.
##
## Bucket growth with a limit, said as the limit that matters: the index may not
## retain anything the list does not. A bucket that kept an entry per removed
## effect would be a leak measured in effects rather than in bytes.
func test_churn_leaves_no_bucket_behind() -> void:
	var nothing: Array[GameplayEffectModifier] = []
	for _round: int in STACK_SEARCHES:
		var active: ActiveGameplayEffect = asc.apply_gameplay_effect(
			EffectFactory.infinite(nothing), asc, 1.0
		)
		asc.remove_active_effect(active)

	assert_eq(asc.effects.active_count(), 0, "nothing is active")
	assert_eq(asc.effects.index.filed_count(), 0, "and nothing is filed")
#endregion


#region What is recorded
## Every load named above, timed and written down.
##
## Nothing here fails for a time. What it fails for is a measurement it could
## not take, which is the only thing about a benchmark a suite can honestly
## assert.
func test_every_load_named_above_is_measured_and_recorded() -> void:
	var rows: Array[String] = []
	for scale: int in EFFECT_SCALES:
		rows.append(_timed("apply effects", scale, _applying.bind(scale)))
	for scale: int in ABILITY_SCALES:
		rows.append(_timed("grant abilities", scale, _granting.bind(scale)))
	rows.append(_timed("tag lookups", TAG_LOOKUPS, _looking_up.bind(TAG_LOOKUPS)))
	rows.append(
		_timed(
			"tag-change reevaluations",
			TAG_CHANGE_REEVALUATIONS,
			_reevaluating.bind(TAG_CHANGE_REEVALUATIONS)
		)
	)
	rows.append(
		_timed("stack candidate searches", STACK_SEARCHES, _searching.bind(STACK_SEARCHES))
	)

	assert_eq(rows.size(), 9, "every load the phase names was measured")
	_write(rows)
	assert_true(FileAccess.file_exists(RECEIPT), "and written down")
#endregion


#region The loads
func _applying(scale: int) -> void:
	var nothing: Array[GameplayEffectModifier] = []
	for _index: int in scale:
		asc.apply_gameplay_effect(EffectFactory.infinite(nothing), asc, 1.0)
	asc.effects.cleanup()


func _granting(scale: int) -> void:
	var handles: Array[GameplayAbilityHandle] = []
	for _index: int in scale:
		var spec: GameplayAbilitySpec = AbilityFactory.give(asc, Probe.build(ABILITY_TAG))
		if spec != null:
			handles.append(spec.handle)
	for handle: GameplayAbilityHandle in handles:
		asc.remove_ability_handle(handle)


func _looking_up(times: int) -> void:
	asc.tags.add(BURNING)
	for _index: int in times:
		asc.tags.has(BURNING)
	asc.tags.clear(BURNING)


func _reevaluating(times: int) -> void:
	var watching: GameplayEffect = _requiring(BURNING)
	asc.apply_gameplay_effect(watching, asc, 1.0)
	for index: int in times:
		var added: bool = index % 2 == 0
		if added:
			asc.tags.add(BURNING)
		else:
			asc.tags.remove(BURNING)
		asc.emit_tag_change(
			BURNING,
			GameplayTagRuntime.Change.ADDED if added else GameplayTagRuntime.Change.REMOVED,
			1 if added else 0
		)
	asc.effects.cleanup()


func _searching(times: int) -> void:
	var stackable: GameplayEffect = EffectFactory.infinite(
		[] as Array[GameplayEffectModifier]
	)
	stackable.stacking_type = GameplayEffect.StackingType.AGGREGATE_BY_TARGET
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(
		stackable, GameplayEffectContext.new(fixture.owner), 1.0
	)
	spec.source_asc = asc
	for _index: int in times:
		asc.effects.stacking.find_candidate(spec)
#endregion


#region Getting there
## How many candidates one stack search compares with `scale` effects standing.
func _stack_searches_at(scale: int) -> int:
	var stackable: GameplayEffect = EffectFactory.infinite(
		[] as Array[GameplayEffectModifier]
	)
	stackable.stacking_type = GameplayEffect.StackingType.AGGREGATE_BY_TARGET
	asc.apply_gameplay_effect(stackable, asc, 1.0)
	_crowd(scale)

	asc.effects.index.forget_counters()
	asc.apply_gameplay_effect(stackable, asc, 1.0)
	var examined: int = asc.effects.index.stack_candidates_examined
	asc.effects.cleanup()
	return examined


## How many effects one tag change reevaluates with `scale` effects standing.
func _reevaluations_at(scale: int) -> int:
	asc.apply_gameplay_effect(_requiring(BURNING), asc, 1.0)
	_crowd(scale)

	asc.effects.index.forget_counters()
	asc.tags.add(BURNING)
	asc.emit_tag_change(BURNING, GameplayTagRuntime.Change.ADDED, 1)
	var reevaluated: int = asc.effects.index.inhibition_effects_reevaluated
	asc.tags.clear(BURNING)
	asc.effects.cleanup()
	return reevaluated


func _crowd(size: int) -> void:
	var nothing: Array[GameplayEffectModifier] = []
	for _index: int in size:
		asc.apply_gameplay_effect(EffectFactory.infinite(nothing), asc, 1.0)


func _requiring(tag: StringName) -> GameplayEffect:
	var effect: GameplayEffect = EffectFactory.infinite(
		[] as Array[GameplayEffectModifier]
	)
	var query: GameplayTagQuery = GameplayTagQuery.new()
	GameplayTagQueryEdits.add_tag(GameplayTagQueryEdits.ensure_root(query), tag)

	var requirement: GameplayEffectTargetTagRequirementsComponent = (
		GameplayEffectTargetTagRequirementsComponent.new()
	)
	requirement.ongoing_query = query
	effect.components.append(requirement)
	return effect


## One load, warmed up and then measured.
##
## The warm-up run is thrown away rather than averaged in: the first call into a
## path pays for whatever the engine builds lazily, and reporting that as the
## median would say the system is slower than anybody ever experiences.
func _timed(named: String, scale: int, work: Callable) -> String:
	for _warm: int in WARMUP:
		work.call()
	var probe: GameplayPerfProbe = GameplayPerfProbe.measure(work, RUNS)
	return probe.to_row(named, scale)
#endregion


#region The receipt
## The machine, the build, and the numbers.
##
## The machine is written down because the numbers are about it. Comparing a
## median taken here with one taken on another machine is comparing two
## machines, which is the mistake the phase warns against by name.
func _write(rows: Array[String]) -> void:
	DirAccess.make_dir_recursive_absolute(RECEIPT.get_base_dir())
	var file: FileAccess = FileAccess.open(RECEIPT, FileAccess.WRITE)
	assert_not_null(file, "the receipt opened for writing")
	if file == null:
		return
	file.store_string(_header())
	for row: String in rows:
		file.store_line(row)
	file.store_string(_footer())
	file.close()


func _header() -> String:
	# Through typed locals: `get_memory_info()` answers a Dictionary of Variants
	# and `%` binds tighter than `/`, so dividing a formatted line by a megabyte
	# is what the first version of this did.
	var physical: Variant = OS.get_memory_info().get("physical", 0)
	var mebibytes: int = int(str(physical)) / (1024 * 1024)
	var godot: Variant = Engine.get_version_info().get("string", "")
	return (
		"# Indexed search performance certification\n"
		+ "\n"
		+ "Written by `test/unit/test_indexed_search_performance_certification.gd` on every\n"
		+ "suite run. Microseconds, on the machine named below: a number here is a\n"
		+ "fact about that machine and nothing in the suite fails for it. What the\n"
		+ "suite does fail for is structural and is in the table after this one.\n"
		+ "\n"
		+ "## The machine and the build\n"
		+ "\n"
		+ "| what | value |\n"
		+ "|---|---|\n"
		+ "| CPU | %s |\n" % OS.get_processor_name()
		+ "| cores | %d |\n" % OS.get_processor_count()
		+ "| RAM (MiB) | %d |\n" % mebibytes
		+ "| OS | %s %s |\n" % [OS.get_name(), OS.get_version()]
		+ "| Godot | %s |\n" % str(godot)
		+ "| build | %s |\n" % ("debug" if OS.is_debug_build() else "release")
		+ "| warmup runs | %d |\n" % WARMUP
		+ "| measured runs | %d |\n" % RUNS
		+ "\n"
		+ "## What each load cost\n"
		+ "\n"
		+ "| load | scale | runs | p50 us | p95 us | p99 us | objects left |\n"
		+ "|---|---|---|---|---|---|---|\n"
	)


func _footer() -> String:
	return (
		"\n"
		+ "## What the suite actually fails for\n"
		+ "\n"
		+ "The two searches that used to read every effect on a character do not\n"
		+ "grow with how many there are. Asserted rather than reported, because the\n"
		+ "counts are the same on every machine:\n"
		+ "\n"
		+ "- a stack search compares at most the effects sharing its definition,\n"
		+ "  whether a hundred or ten thousand are standing;\n"
		+ "- a tag change reevaluates only the effects whose requirements name that\n"
		+ "  tag or an ancestor of it;\n"
		+ "- a thousand applications and removals leave the index holding nothing.\n"
		+ "\n"
		+ "`test/unit/test_indexed_search_performance_certification.gd::"
		+ "test_the_stack_search_does_not_grow_with_the_crowd`\n"
	)
#endregion
