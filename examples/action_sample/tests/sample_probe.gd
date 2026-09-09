## The seven things this sample exists to demonstrate, checked without a person
## watching.
##
## Deterministic on purpose: no physics query, no timer, no frame it has to wait
## for, nothing random. A sample whose check needed a person to look at it is a
## sample that quietly stops working, and F6.6 runs this same probe against a
## server and a client to say the two agree.
##
## It runs against `SampleWorld` - the scene somebody presses play on - rather
## than against a rig built for it, so what passes here is what they see.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name SampleProbe extends RefCounted


## One thing demonstrated, and whether it was.
class Finding extends RefCounted:
	var what: String = ""
	var held: bool = false

	## What was actually observed, so a failure says more than "no".
	var said: String = ""

	func shown() -> String:
		return "%s: %s (%s)" % [what, "yes" if held else "NO", said]


## Run every demonstration against `world`, in order.
##
## The order is the order somebody would try them, and each leaves the world
## where the next one expects it - a probe whose steps had to be run separately
## would be seven probes.
static func run(world: SampleWorld) -> Array[Finding]:
	var findings: Array[Finding] = []
	if world == null or world.hero == null:
		findings.append(_finding("a world to run in", false, "there is none"))
		return findings

	findings.append(_loadout(world))
	findings.append(_strike(world))
	findings.append(_channel(world))
	findings.append(_slam(world))
	findings.append(_failure_is_visible(world))
	findings.append(_overlay(world))
	return findings


## Whether everything held.
static func all_held(findings: Array[Finding]) -> bool:
	for finding: Finding in findings:
		if not finding.held:
			return false
	return true


#region The six
## One call grants the loadout, and the character has all of it.
static func _loadout(world: SampleWorld) -> Finding:
	var granted: int = world.hero.asc.get_ability_specs().size()
	var has_attributes: bool = world.hero.asc.get_attribute_base(SampleAttributes.HEALTH) > 0.0
	return _finding(
		"a loadout granted in one call",
		granted == 3 and has_attributes,
		"%d abilities and an attribute set" % granted
	)


## A strike lands, takes health off, and plays its burst.
static func _strike(world: SampleWorld) -> Finding:
	var dummy: SampleHero = world.dummies[0]
	var before: float = dummy.asc.get_attribute_current(SampleAttributes.HEALTH)

	var result: GameplayAbilityActivationResult = world.hero.strike(dummy)
	var after: float = dummy.asc.get_attribute_current(SampleAttributes.HEALTH)

	return _finding(
		"an instant attack with a burst cue",
		result.is_ok() and is_equal_approx(before - after, SampleEffects.STRIKE_DAMAGE),
		"health %s -> %s" % [before, after]
	)


## A channel stays up, drains, and takes its loop off when it ends.
static func _channel(world: SampleWorld) -> Finding:
	var channel: SampleChannel = world.hero.ability_tagged(SampleChannel.TAG) as SampleChannel
	if channel == null:
		return _finding("a channel with a looping cue", false, "the ability was not granted")

	# Counted rather than asked of the ability: what has to come off the
	# character is the drain itself, and an ability that forgot the effect while
	# clearing its own field would answer "not channelling" over a mana drain
	# that runs for the rest of the game.
	var before: int = world.hero.asc.get_active_effects().size()
	world.hero.channel()
	var up: bool = channel.is_channelling()
	var draining: bool = world.hero.asc.get_active_effects().size() == before + 1
	var looping: bool = _cue_is_running(world, world.hero, SampleCues.CHANNEL_LOOP)

	channel.end_ability()
	var down: bool = not channel.is_channelling()
	var drained: bool = world.hero.asc.get_active_effects().size() == before
	var stopped: bool = not _cue_is_running(world, world.hero, SampleCues.CHANNEL_LOOP)

	return _finding(
		"a channel with a persistent looping cue",
		up and draining and looping and down and drained and stopped,
		"up=%s draining=%s looping=%s ended=%s drain gone=%s cue stopped=%s"
		% [up, draining, looping, down, drained, stopped]
	)


## A slam aims, shows a ring, lands where it was confirmed, and staggers.
static func _slam(world: SampleWorld) -> Finding:
	var slam: SampleGroundSlam = world.hero.ability_tagged(SampleGroundSlam.TAG) as SampleGroundSlam
	if slam == null:
		return _finding("a ground area effect", false, "the ability was not granted")

	world.hero.aim_slam()
	var aiming: bool = slam.is_aiming()

	var victim: SampleHero = world.dummies[1]
	var before: float = victim.asc.get_attribute_current(SampleAttributes.HEALTH)
	slam.submit_target_data(_confirmed_at(Vector3(4.0, 0.0, 0.0), victim))
	var after: float = victim.asc.get_attribute_current(SampleAttributes.HEALTH)

	var staggered: bool = victim.asc.has_tag(SampleEffects.STAGGERED)
	return _finding(
		"an aimed area effect with a reticle and a preset",
		aiming
		and is_equal_approx(before - after, SampleEffects.SLAM_DAMAGE)
		and staggered
		and slam.landed_at.is_equal_approx(Vector3(4.0, 0.0, 0.0)),
		"aimed=%s health %s -> %s staggered=%s at %s"
		% [aiming, before, after, staggered, slam.landed_at]
	)


## A refusal says which refusal it was, as a tag a game's own UI can react to.
static func _failure_is_visible(world: SampleWorld) -> Finding:
	var staggered: SampleHero = world.dummies[1]
	var refused: GameplayAbilityActivationResult = staggered.aim_slam()

	# The console is the surface a person actually reads it on, and it names the
	# tag rather than only the status - which is what a game reacts to.
	var said: String = world.console("gas.activate %s Slam" % staggered.name)
	var tag: StringName = AbilityFailureTags.of(AbilityRuntime.ActivationError.BLOCKED_TAG)

	return _finding(
		"a refusal visible as a failure tag",
		not refused.is_ok() and said.contains(String(tag)),
		said
	)


## The overlay says what the hero is, on four pages, with no editor anywhere.
static func _overlay(world: SampleWorld) -> Finding:
	if world.overlay == null:
		return _finding("a runtime debug overlay", false, "the overlay scene is missing")

	var pages: int = world.overlay.pages().size()
	var drawn: int = 0
	var taken: GasRuntimeSnapshot = world.overlay.snapshot()
	for page: GasDebugPage in world.overlay.pages():
		if not page.rows(taken).is_empty():
			drawn += 1

	return _finding(
		"a runtime debug overlay outside the editor",
		pages == 4 and drawn == pages and not Engine.is_editor_hint(),
		"%d pages, %d of them with something to say" % [pages, drawn]
	)
#endregion


#region Getting there
static func _finding(what: String, held: bool, said: String) -> Finding:
	var finding: Finding = Finding.new()
	finding.what = what
	finding.held = held
	finding.said = said
	return finding


## What a confirmed aim hands over: one place, and whoever was standing in it.
##
## Built here rather than queried from physics, which is what makes this
## deterministic: a probe that asked the world who was in a circle would be a
## probe that answers differently depending on when the physics server last ran.
static func _confirmed_at(spot: Vector3, victim: Node) -> GameplayAbilityTargetData:
	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	data.append_location(spot)
	data.append_node(victim)
	return data


static func _cue_is_running(world: SampleWorld, on: Node, tag: StringName) -> bool:
	return SampleCues.is_playing(world, on, tag)
#endregion
