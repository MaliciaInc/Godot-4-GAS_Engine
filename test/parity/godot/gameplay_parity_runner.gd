## Runs a case and reports every way Godot disagreed with the reference.
##
## The whole of the differential half lives here. A case says what the reference
## does; this stands a character up, does the one thing the case names, and
## reads back all eleven dimensions - so a disagreement is reported in the
## dimension it happened in rather than as one number being wrong.
##
## The identity and authoring rules are named rather than written out per case.
## A case says which rule applies; the two tables below say what checking it
## means. That is the difference between a corpus of contracts and a corpus of
## assertions copied eleven times.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayParityRunner extends RefCounted

const Fixture = preload("res://test/fixtures/asc_fixture.gd")

const TOLERANCE: float = 0.0001

## The signals a case may name, and how they are watched.
##
## Named on the component rather than discovered, because a corpus that watched
## whatever signals happened to exist would quietly stop watching one that was
## renamed.
const WATCHED: Array[StringName] = [
	&"attribute_changed",
	&"tag_added",
	&"tag_removed",
	&"tag_count_changed",
	&"active_effect_added",
	&"active_effect_removed",
	&"active_effect_stack_changed",
	&"gameplay_effect_executed",
	&"cue_executed",
]

## What a case can claim about handles, and what claiming it means.
const IDENTITY_RULES: Array[StringName] = [
	## Every running effect answers to a handle, and no two share one.
	&"one_handle_per_application",
	## Stacking does not mint a second handle: two of a thing is one application.
	&"stacking_keeps_one_handle",
	## Nothing is running, so there is nothing to be addressed.
	&"no_handles",
]

## What a case claims about authoring: the name of the method a person would
## reach for in the Composer to do what the case did, or this, when what it did
## is engine plumbing nobody authors.
##
## A name rather than a rule, because the interesting claim is not "somebody
## can author something" - it is that this particular thing is on the palette,
## and the palette is the one place that can answer it.
const ENGINE_PLUMBING: StringName = &"engine_plumbing"


## Stand a character up, do the one thing, and read everything back.
static func run(case: GameplayParityCase, host: Node) -> GameplayParityResult:
	var result: GameplayParityResult = GameplayParityResult.of(case)
	if not case.is_complete():
		result.disagree("the case does not say all eleven things")
		return result

	var fixture: ASCFixture = Fixture.create("Parity")
	host.add_child(fixture.owner)
	fixture.asc.set_process(false)
	for name: StringName in case.attributes:
		fixture.asc.set_attribute_base(name, case.attributes[name])
	for tag: StringName in case.tags:
		fixture.asc.add_tag(tag)

	var fired: Array[StringName] = []
	_watch(fixture.asc, fired)
	case.input.call(fixture)

	_check_attributes(case, fixture, result)
	_check_tags(case, fixture, result)
	_check_effects(case, fixture, result)
	_check_signals(case, fired, result)
	_check_identity(case, fixture, result)
	_check_authoring(case, result)

	fixture.owner.queue_free()
	return result


## Record every watched signal by name, whatever it carries.
##
## Bound by name rather than by one lambda per signal, because a list of nine
## lambdas is nine places for one of them to append the wrong name.
static func _watch(asc: AbilitySystemComponent, fired: Array[StringName]) -> void:
	for name: StringName in WATCHED:
		asc.connect(name, func(
			_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null
		) -> void: fired.append(name))


static func _check_attributes(
	case: GameplayParityCase, fixture: ASCFixture, result: GameplayParityResult
) -> void:
	for name: StringName in case.expected_attributes:
		var found: float = fixture.asc.get_attribute_current(name)
		if not is_equal_approx(found, case.expected_attributes[name]):
			result.disagree(
				"attribute %s is %.4f and the reference says %.4f"
				% [name, found, case.expected_attributes[name]]
			)


static func _check_tags(
	case: GameplayParityCase, fixture: ASCFixture, result: GameplayParityResult
) -> void:
	for tag: StringName in case.expected_tags:
		var held: int = fixture.asc.tags.count_exact(tag)
		if held != case.expected_tags[tag]:
			result.disagree(
				"tag %s is held %d times and the reference says %d"
				% [tag, held, case.expected_tags[tag]]
			)


static func _check_effects(
	case: GameplayParityCase, fixture: ASCFixture, result: GameplayParityResult
) -> void:
	var running: int = fixture.asc.get_active_effects().size()
	if running != case.expected_effects:
		result.disagree(
			"%d effects are running and the reference says %d" % [running, case.expected_effects]
		)


## The set, then the subsequence.
##
## Two checks because they are two claims: that an announcement happened at all,
## and that two of them happened in an order somebody depends on.
static func _check_signals(
	case: GameplayParityCase, fired: Array[StringName], result: GameplayParityResult
) -> void:
	for name: StringName in case.expected_signals:
		if not fired.has(name):
			result.disagree("%s never fired, and the reference says it does" % name)

	var at: int = 0
	for name: StringName in case.expected_order:
		var found: int = fired.find(name, at)
		if found < 0:
			result.disagree(
				"%s did not fire after what the reference says comes before it" % name
			)
			return
		at = found + 1


static func _check_identity(
	case: GameplayParityCase, fixture: ASCFixture, result: GameplayParityResult
) -> void:
	if not IDENTITY_RULES.has(case.expected_identity):
		result.disagree("%s is not an identity rule this runner knows" % case.expected_identity)
		return

	var running: Array[ActiveGameplayEffect] = fixture.asc.get_active_effects()
	var handles: Array[int] = []
	for active: ActiveGameplayEffect in running:
		if active.handle == null or not active.handle.is_valid():
			result.disagree("an effect is running with no handle to address it by")
			continue
		if handles.has(active.handle.id):
			result.disagree("two applications answer to one handle")
		handles.append(active.handle.id)

	match case.expected_identity:
		&"no_handles":
			if not handles.is_empty():
				result.disagree("%d handles exist and the reference says none do" % handles.size())
		&"stacking_keeps_one_handle":
			if handles.size() != 1:
				result.disagree(
					"%d handles exist and stacking should have kept one" % handles.size()
				)
		_:
			if handles.size() != running.size():
				result.disagree("not every application is addressable")


## Whether what the case exercised is something a person can author.
##
## Asked of the Composer's own catalog rather than of a list kept here: a second
## list would be the thing that stopped matching the palette, and it would stop
## matching it silently.
static func _check_authoring(case: GameplayParityCase, result: GameplayParityResult) -> void:
	if case.expected_authoring == ENGINE_PLUMBING:
		return
	if ComposerCatalog.sources_offering(case.expected_authoring).is_empty():
		result.disagree(
			"%s is not on the palette, so nothing a person authors reaches this contract"
			% case.expected_authoring
		)
