## Measured, not guessed - and the part that does not depend on the machine,
## asserted.
##
## The phase asks for numbers at three scales across seven workloads, with p50,
## p95 and p99 and an object delta, and it asks for them before anything is
## indexed or batched. So the numbers are recorded and nothing here fails for
## being slow: a threshold measured on one machine is a fact about that machine,
## and a suite that failed on somebody's laptop for it is a suite people learn
## to ignore.
##
## What is asserted is what a machine cannot change. Nothing is retained after a
## teardown. The one place gameplay depends on chance takes a seed, and the same
## seed gives the same run. The order targets are reported in is the order they
## were captured in. And physics is not sold as any of that.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")

const RESULTS: String = "res://artifacts/parity/results"
const RESULTS_FILE: String = RESULTS + "/performance.md"

## Enough runs for a percentile to mean something, few enough that the biggest
## scale does not turn the suite into something people skip.
const RUNS: int = 5

const HEADER: String = (
	"# Performance and determinism\n"
	+ "\n"
	+ "Written by `test/unit/test_performance_and_determinism.gd` on every suite\n"
	+ "run. Microseconds, on whatever machine ran it: a number here is a fact\n"
	+ "about that machine and nothing in the suite fails for it. Nothing is\n"
	+ "indexed or batched on the strength of these yet, which is the order the\n"
	+ "phase asks for - one thing has been, and it is named below.\n"
	+ "\n"
	+ "## What these measurements found\n"
	+ "\n"
	+ "Applying effects to one character is super-linear: ten cost a few\n"
	+ "milliseconds, a hundred cost tens, a thousand cost seconds. Composing an\n"
	+ "attribute used to walk every contribution on the entity once per channel,\n"
	+ "so a set of five attributes walked the whole list twenty times. That half\n"
	+ "is indexed by attribute now, and is most of the difference between the\n"
	+ "first measurement and this one.\n"
	+ "\n"
	+ "What is left is the passes each application makes over every effect that\n"
	+ "is already running - inhibition, stacking, the effect components. Measured\n"
	+ "and named rather than optimised: indexing those changes how application is\n"
	+ "ordered, and that belongs in a package of its own.\n"
	+ "\n"
	+ "| workload | scale | runs | p50 us | p95 us | p99 us | objects left |\n"
	+ "|---|---|---|---|---|---|---|\n"
)


#region What it costs
## Seven workloads, three scales each, measured and written down.
func test_every_workload_is_measured_at_every_scale() -> void:
	var rows: Array[String] = []
	var measured: int = 0

	for scale: int in GameplayPerfScenarios.SCALES:
		for named: String in _workloads():
			var scenarios: GameplayPerfScenarios = GameplayPerfScenarios.on(self)
			var work: Callable = Callable(scenarios, named).call(scale)
			var probe: GameplayPerfProbe = GameplayPerfProbe.measure(work, RUNS)
			rows.append(probe.to_row(named, scale))
			scenarios.clean()
			measured += 1

			assert_eq(probe.runs(), RUNS, "%s at %d was actually run" % [named, scale])
			assert_gt(probe.at(50.0), 0.0, "%s at %d took a measurable time" % [named, scale])

	_write(rows)
	assert_eq(
		measured, GameplayPerfScenarios.SCALES.size() * _workloads().size(),
		"every workload at every scale"
	)


func _workloads() -> Array[String]:
	return [
		"components",
		"effects",
		"tag_lookups",
		"recomposition",
		"passive_reevaluation",
		"targeting_queries",
		"network_serialization",
	] as Array[String]
#endregion


#region What it keeps
## A hundred characters stood up, torn down, and nothing left holding anything.
##
## The other way an ability system goes wrong at scale, and the one the timings
## would never show: a workload that runs in microseconds and keeps four
## hundred objects per call is a session that dies after twenty minutes.
func test_standing_a_hundred_characters_up_and_taking_them_down_keeps_nothing() -> void:
	var scenarios: GameplayPerfScenarios = GameplayPerfScenarios.on(self)
	var before: float = Performance.get_monitor(Performance.OBJECT_COUNT)

	for _round: int in 3:
		scenarios.components(100).call()
		for node: Node in scenarios.built:
			var asc: AbilitySystemComponent = AbilitySystemLocator.find_for_node(node)
			if asc != null:
				asc.dispose()
		scenarios.clean()

	var after: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	assert_almost_eq(
		after, before, 8.0,
		"three hundred characters came and went and nothing was retained"
	)
#endregion


#region What a seed decides
## The one place gameplay depends on chance takes a seed.
##
## A chance-to-apply component asks an RNG the runtime owns. Seeded the same
## way twice, the same applications land - which is the whole of what a
## deterministic contract can promise about randomness: not that there is none,
## but that a game can decide it.
func test_the_same_seed_gives_the_same_run() -> void:
	var first: Array[bool] = _coin_flips(20, 12345)
	var again: Array[bool] = _coin_flips(20, 12345)
	var different: Array[bool] = _coin_flips(20, 99)

	assert_eq(first, again, "the same seed, the same run")
	assert_ne(first, different, "and a different seed is a different one")


func _coin_flips(count: int, seed_value: int) -> Array[bool]:
	var fixture: ASCFixture = Fixture.create("Chance")
	add_child_autofree(fixture.owner)
	fixture.asc.set_process(false)
	fixture.asc.effects.components.rng.seed = seed_value

	var chance: GameplayEffectChanceToApplyComponent = (
		GameplayEffectChanceToApplyComponent.new()
	)
	chance.chance = 0.5
	var effect: GameplayEffect = EffectFactory.infinite(
		[] as Array[GameplayEffectModifier]
	)
	effect.components.append(chance)

	var landed: Array[bool] = []
	for _flip: int in count:
		var result: GameplayEffectApplicationResult = EffectFactory.apply_result(
			fixture.asc, effect
		)
		landed.append(result.is_ok())
	return landed
#endregion


#region What the index must not let go of
## The list a caller is handed is a copy.
##
## Composing reads the stored list directly, for the speed; everybody else
## gets a copy, because a caller that appended to the stored one would be
## adding a contribution past the validation every one of them goes through
## on the way in - and the index and the ordered list would disagree from
## then on.
func test_the_contributions_a_caller_is_handed_are_not_the_stored_ones() -> void:
	var fixture: ASCFixture = Fixture.create("Copies")
	add_child_autofree(fixture.owner)
	EffectFactory.apply(
		fixture.asc,
		EffectFactory.infinite(
			[EffectFactory.add(&"attack", 3.0)] as Array[GameplayEffectModifier]
		)
	)
	var handed: Array[AttributeModifierContribution] = (
		fixture.asc.attributes.contributions_for(&"attack")
	)
	assert_eq(handed.size(), 1, "one contribution to hand over")

	handed.clear()

	assert_eq(
		fixture.asc.attributes.contributions_for(&"attack").size(), 1,
		"and clearing the copy left the entity's own alone"
	)


## A reset clears both lists, or the entity keeps buffs it no longer has.
##
## Asked of the runtime directly rather than through `cleanup()`, because by
## the time cleanup calls this the effects have already taken their own
## contributions out one at a time and there is nothing left for it to clear.
## The method is public and its contract is its own: everything, gone. A
## caller using it on a live component - which is what cleanup is, a reusable
## reset rather than a teardown - would otherwise put every modifier from
## before the reset back into the next composition while the ordered list
## said they were gone.
func test_a_reset_clears_the_index_as_well_as_the_list() -> void:
	var fixture: ASCFixture = Fixture.create("Reset")
	add_child_autofree(fixture.owner)
	fixture.set_base(&"attack", 10.0)
	EffectFactory.apply(
		fixture.asc,
		EffectFactory.infinite(
			[EffectFactory.add(&"attack", 5.0)] as Array[GameplayEffectModifier]
		)
	)
	assert_almost_eq(
		fixture.asc.get_attribute_current(&"attack"), 15.0, 0.001, "the buff is on"
	)

	fixture.asc.attributes.clear_contributions()

	assert_eq(
		fixture.asc.attributes.contributions_for(&"attack").size(), 0,
		"nothing is contributing any more"
	)
	fixture.asc.attributes.recompose(&"attack")
	assert_almost_eq(
		fixture.asc.get_attribute_current(&"attack"), 10.0, 0.001,
		"and the value is what the character is again"
	)
#endregion


#region What order things are in
## Targets are reported in the order they were captured.
##
## Which matters wherever the result depends on order - the first thing hit, the
## nearest three - and is a promise this engine can keep. Physics is not: the
## order a query reports overlapping bodies in is the physics server's, and
## nothing here can sell that as a contract. Said out loud rather than left for
## somebody to find out.
func test_targets_are_reported_in_the_order_they_were_captured() -> void:
	var aimed: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	var order: Array[Node] = []
	for index: int in 6:
		var node: Node = Node.new()
		node.name = "Target%d" % index
		add_child_autofree(node)
		order.append(node)
		aimed.append_node(node)

	assert_eq(aimed.get_target_nodes(), order, "capture order, every time")
#endregion


## The results, where somebody can read them.
func _write(rows: Array[String]) -> void:
	DirAccess.make_dir_recursive_absolute(RESULTS)
	var file: FileAccess = FileAccess.open(RESULTS_FILE, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(HEADER + "\n".join(rows) + "\n")
	file.close()
