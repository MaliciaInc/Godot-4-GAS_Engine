## Measure something, several times, and say what it cost.
##
## Percentiles rather than an average, because an average hides the case that
## matters: a recomposition that is fast on nine frames out of ten and eight
## milliseconds on the tenth is a hitch a player sees, and an average says it is
## fine. p50, p95 and p99 are what the phase asks for and what a frame budget is
## actually spent against.
##
## Object count as well as time, because the other way an ability system goes
## wrong at scale is not speed: it is what it kept. A workload that runs in
## microseconds and leaves four hundred objects behind per call is a session
## that dies after twenty minutes, and nothing about the timing would say so.
##
## Nothing here asserts a threshold. A number measured on one machine is a fact
## about that machine, and a suite that failed on somebody's laptop for being
## slow would be a suite people learn to ignore. What is asserted elsewhere is
## what does not depend on the machine: that nothing is retained, and that the
## same seed produces the same run.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayPerfProbe extends RefCounted

## Every run's cost, in microseconds.
var samples: Array[float] = []

var objects_before: int = 0
var objects_after: int = 0


## Run `work` `runs` times, timing each one. `cleanup` runs between them and is
## not timed: freeing what a workload made is not part of what it costs to make.
static func measure(work: Callable, runs: int, cleanup: Callable = Callable()) -> GameplayPerfProbe:
	var probe: GameplayPerfProbe = GameplayPerfProbe.new()
	probe.objects_before = _objects()

	for _run: int in runs:
		var started: int = Time.get_ticks_usec()
		work.call()
		probe.samples.append(float(Time.get_ticks_usec() - started))
		if cleanup.is_valid():
			cleanup.call()

	probe.objects_after = _objects()
	return probe


## The cost at a percentile, by nearest rank.
##
## Nearest rank rather than interpolation: with the small sample counts a suite
## can afford, an interpolated p99 is a number invented between two measurements
## and reported as though it had been observed.
func at(percentile: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	# ceilf and not ceil: the untyped one answers a Variant, and int() will not
	# take one - the same refusal that keeps an unchecked conversion out of the
	# engine keeps it out of the thing measuring the engine.
	var rank: int = int(ceilf(percentile / 100.0 * float(sorted.size()))) - 1
	return sorted[clampi(rank, 0, sorted.size() - 1)]


## What the whole measurement left behind, if anything.
func object_delta() -> int:
	return objects_after - objects_before


func runs() -> int:
	return samples.size()


## One row of the results table.
func to_row(named: String, scale: int) -> String:
	return "| %s | %d | %d | %.1f | %.1f | %.1f | %d |" % [
		named, scale, runs(), at(50.0), at(95.0), at(99.0), object_delta()
	]


## Through a typed local: `Performance.get_monitor` answers a Variant, and
## handing one straight to `int()` is the unchecked conversion the strict
## pass refuses - here, where a wrong reading would silently become a wrong
## object delta.
static func _objects() -> int:
	var counted: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	return int(counted)
