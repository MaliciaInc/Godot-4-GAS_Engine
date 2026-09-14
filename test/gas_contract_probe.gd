## The engine's contracts, measured on this game's own battlers and abilities.
##
## `gas_probe` plays a fight and says one thing: both arenas finish. It cannot say
## whether a hit took off the right number, whether a cost was charged, whether a
## cooldown lifted on the right turn - accuracy is rolled, and the fight runs on
## a wall clock. This drives the same seam the arena drives, `Battler.act()`, one
## turn at a time and on nothing but this game's authored content, so every
## number it reads is the number the engine promised.
##
## Deterministic by choosing what cannot miss: the wolf's sweep and the
## squirrel's heal carry no accuracy of their own, and every battler here stands
## on the bear's attributes, which carry no evasion. Punch rolls, so it is used
## only where the hit does not matter - its cost and its cooldown.
##
## @meta_license: MIT
extends Node

const BEAR_ATTRIBUTES: String = "res://combat/battlers/bear/bear_attributes.tres"
const SWEEP: String = "res://combat/battlers/wolf/area_attack.tscn"
const HEAL: String = "res://combat/battlers/squirrel/heal_friendly.tscn"
const FOCUS: String = "res://combat/battlers/bear/focus_attack.tscn"
const PUNCH: String = "res://combat/battlers/bear/player_melee_action.tscn"

const COOLDOWN: StringName = &"Cooldown.Punch"
const HASTE: float = 10.0
## Real seconds a turn gets before it is called stuck.
const TURN_SECONDS: float = 8.0

const CASES: Array[String] = [
	"damage", "live_attack", "isolation", "overkill", "corpse", "heal_clamp",
	"heal_full", "cost_refused", "cost_paid", "cooldown", "energy_clamp",
	"buff", "hit_clamp", "max_drop", "cancel_windup", "cancel_travel",
]

var _passed: int = 0
var _report: Array[String] = []
var _finished: Array[String] = []
var _stage: Node2D = null


## What a battler said about itself, heard through its own signals.
class Ears extends RefCounted:
	var damaged: Array[float] = []
	var healed: Array[float] = []
	var downed: int = 0

	func clear() -> void:
		damaged.clear()
		healed.clear()
		downed = 0


func _ready() -> void:
	_stage = Node2D.new()
	add_child(_stage)
	await get_tree().process_frame
	Engine.time_scale = HASTE

	var wolf: Battler = _spawn("Wolf", [SWEEP], 0.0)
	var target: Battler = _spawn("Target", [], 600.0)
	var twin: Battler = _spawn("Twin", [], 700.0)
	await get_tree().process_frame

	await _case_damage(wolf, target)
	await _case_live_attack(wolf, target)
	_case_isolation(target, twin)
	await _case_overkill(wolf, target)
	var nutsy: Battler = _spawn("Nutsy", [HEAL], 300.0)
	await get_tree().process_frame
	await _case_corpse(wolf, nutsy, target)
	await _case_heal_clamp(nutsy, twin)
	await _case_heal_full(nutsy, twin)
	var baloo: Battler = _spawn("Baloo", [FOCUS, PUNCH], -300.0)
	var dummy: Battler = _spawn("Dummy", [], 800.0)
	await get_tree().process_frame
	await _case_cost_refused(baloo, dummy)
	await _case_cost_paid(baloo, dummy)
	_case_cooldown(baloo)
	_case_energy_clamp(baloo)
	await _case_buff(baloo)
	await _case_hit_clamp(baloo)
	_case_max_drop(twin)
	await _case_cancel_windup(wolf)
	await _case_cancel_travel(wolf)

	Engine.time_scale = 1.0
	var missing: Array[String] = []
	for name: String in CASES:
		if not _finished.has(name):
			missing.append(name)
	_check("every case ran to its last line", missing.is_empty(), "stopped part way: %s" % ", ".join(missing))

	print("\n===== GAS CONTRACTS on THIS GAME =====")
	for line: String in _report:
		print(line)
	var failed: int = _report.size() - _passed
	print("%d checks, %d passed, %d to look at" % [_report.size(), _passed, failed])
	print("GAS_CONTRACT_RESULT: %s passed=%d failed=%d" % ["PASS" if failed == 0 else "FAIL", _passed, failed])
	get_tree().quit(0 if failed == 0 else 1)


#region Saying what happened
func _check(what: String, held: bool, detail: String = "") -> void:
	_passed += 1 if held else 0
	_report.append("%s %-64s %s" % ["  ok " if held else "FAIL", what, detail])


func _finish(case_name: String) -> void:
	_finished.append(case_name)
#endregion


#region The game's side
func _spawn(named: String, scenes: Array[String], x: float) -> Battler:
	var battler: Battler = Battler.new()
	battler.name = named
	battler.attributes = load(BEAR_ATTRIBUTES) as BattlerAttributes
	var loaded: Array[PackedScene] = []
	for path: String in scenes:
		loaded.append(load(path) as PackedScene)
	battler.ability_scenes = loaded
	battler.position = Vector2(x, 0.0)
	_stage.add_child(battler)
	return battler


func _ears(battler: Battler) -> Ears:
	var ears: Ears = Ears.new()
	battler.damaged.connect(func _hurt(amount: float) -> void: ears.damaged.append(amount))
	battler.healed.connect(func _mended(amount: float) -> void: ears.healed.append(amount))
	battler.downed.connect(func _fell() -> void: ears.downed += 1)
	return ears


func _ability(battler: Battler, index: int) -> BattlerAbility:
	var spec: GameplayAbilitySpec = battler.asc.ability_runtime.get_spec(battler.granted[index])
	return spec.per_actor_instance as BattlerAbility if spec != null else null


func _spec(battler: Battler, index: int) -> GameplayAbilitySpec:
	return battler.asc.ability_runtime.get_spec(battler.granted[index])


func _error(battler: Battler, index: int) -> String:
	return AbilityRuntime.ActivationError.keys()[
		battler.asc.ability_runtime.activation_error(_spec(battler, index))
	]


func _health(battler: Battler) -> float:
	return battler.attribute(BattlerAttributes.HEALTH)


## One turn through the arena's own seam. Answers how many times the turn said it
## was over - the arena listens once, so anything but one is a fault.
func _act(caster: Battler, index: int, targets: Array[Battler]) -> int:
	var turns: Array[int] = [0]
	var counter: Callable = func _turned() -> void: turns[0] += 1
	caster.turn_finished.connect(counter)
	caster.act(caster.granted[index], targets)
	await _until(func _over() -> bool: return turns[0] > 0)
	for _frame: int in 5:
		await get_tree().process_frame
	caster.turn_finished.disconnect(counter)
	return turns[0]


func _until(condition: Callable, seconds: float = TURN_SECONDS) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _lasting_add(attribute_name: StringName, amount: float) -> GameplayEffect:
	var value: GameplayScalableFloat = GameplayScalableFloat.new()
	value.value = amount
	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = value
	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = attribute_name
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude
	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INFINITE
	effect.modifiers = [modifier] as Array[GameplayEffectModifier]
	return effect


func _instant_add(attribute_name: StringName, amount: float) -> GameplayEffect:
	var effect: GameplayEffect = _lasting_add(attribute_name, amount)
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	return effect
#endregion


#region Damage
func _case_damage(wolf: Battler, target: Battler) -> void:
	_ability(wolf, 0).base_damage = 20.0
	var ears: Ears = _ears(target)
	var turns: int = await _act(wolf, 0, [target] as Array[Battler])
	_check("a sweep takes the caster's attack plus its own bite", is_equal_approx(_health(target), 70.0), "health %.1f, expected 70" % _health(target))
	_check("the battler says it was hurt, once, by that much", ears.damaged == ([30.0] as Array[float]), "%s" % [ears.damaged])
	_check("the turn says it is over exactly once", turns == 1, "%d" % turns)
	_check("and the caster is no longer acting", not wolf.asc.has_tag_exact(Battler.ACTING))
	_finish("damage")


func _case_live_attack(wolf: Battler, target: Battler) -> void:
	var buff: ActiveGameplayEffect = wolf.asc.apply_gameplay_effect(_lasting_add(BattlerAttributes.ATTACK, 10.0))
	_check("an attack buff lands on the caster", is_equal_approx(wolf.attribute(BattlerAttributes.ATTACK), 20.0), "attack %.1f" % wolf.attribute(BattlerAttributes.ATTACK))
	await _act(wolf, 0, [target] as Array[Battler])
	_check("and the next blow is read at that attack", is_equal_approx(_health(target), 30.0), "health %.1f, expected 30" % _health(target))
	if buff != null:
		wolf.asc.remove_active_effect(buff)
	_check("and taking the buff away returns the attack exactly", is_equal_approx(wolf.attribute(BattlerAttributes.ATTACK), 10.0), "attack %.1f" % wolf.attribute(BattlerAttributes.ATTACK))
	_finish("live_attack")


func _case_isolation(target: Battler, twin: Battler) -> void:
	_check("two battlers from one attributes file are two pools", is_equal_approx(_health(twin), 100.0) and _health(target) < 100.0, "target %.1f, twin %.1f" % [_health(target), _health(twin)])
	_finish("isolation")


func _case_overkill(wolf: Battler, target: Battler) -> void:
	_ability(wolf, 0).base_damage = 999.0
	var ears: Ears = _ears(target)
	await _act(wolf, 0, [target] as Array[Battler])
	_check("an overkill blow stops at zero", is_equal_approx(_health(target), 0.0), "health %.1f" % _health(target))
	_check("and the base is not left below it", target.asc.get_attribute_base(BattlerAttributes.HEALTH) >= 0.0, "base %.1f" % target.asc.get_attribute_base(BattlerAttributes.HEALTH))
	_check("the battler reports what it actually lost", ears.damaged == ([30.0] as Array[float]), "%s" % [ears.damaged])
	_check("it is downed once, and tagged so", ears.downed == 1 and target.is_downed(), "downed %d" % ears.downed)
	_finish("overkill")


func _case_corpse(wolf: Battler, nutsy: Battler, target: Battler) -> void:
	var ears: Ears = _ears(target)
	await _act(wolf, 0, [target] as Array[Battler])
	_check("a blow at a downed battler lands nothing", ears.damaged.is_empty() and ears.downed == 0, "damaged %s downed %d" % [ears.damaged, ears.downed])
	await _act(nutsy, 0, [target] as Array[Battler])
	_check("and a heal does not raise it", is_equal_approx(_health(target), 0.0) and ears.healed.is_empty(), "health %.1f healed %s" % [_health(target), ears.healed])
	_finish("corpse")
#endregion


#region Healing
func _case_heal_clamp(nutsy: Battler, twin: Battler) -> void:
	twin.asc.set_attribute_base(BattlerAttributes.HEALTH, 80.0)
	var ears: Ears = _ears(twin)
	await _act(nutsy, 0, [twin] as Array[Battler])
	_check("a heal past the maximum stops at the maximum", is_equal_approx(_health(twin), 100.0), "health %.1f" % _health(twin))
	_check("and the battler reports the twenty it got, not the fifty", ears.healed == ([20.0] as Array[float]), "%s" % [ears.healed])
	_finish("heal_clamp")


func _case_heal_full(nutsy: Battler, twin: Battler) -> void:
	var ears: Ears = _ears(twin)
	var changes: Array[int] = [0]
	var counter: Callable = func _moved(attribute_name: StringName, _o: float, _n: float, _s: GameplayEffectSpec) -> void:
		if attribute_name == BattlerAttributes.HEALTH:
			changes[0] += 1
	twin.asc.attribute_changed.connect(counter)
	await _act(nutsy, 0, [twin] as Array[Battler])
	twin.asc.attribute_changed.disconnect(counter)
	_check("a heal at full health announces no change", changes[0] == 0 and ears.healed.is_empty(), "%d changes, healed %s" % [changes[0], ears.healed])
	_finish("heal_full")
#endregion


#region Costs and cooldowns
func _case_cost_refused(baloo: Battler, dummy: Battler) -> void:
	var punch: BattlerAbility = _ability(baloo, 1)
	_check("with no energy, Punch is refused for resources", _error(baloo, 1) == "INSUFFICIENT_RESOURCES", _error(baloo, 1))
	punch.targets = [dummy] as Array[Battler]
	var result: GameplayAbilityActivationResult = baloo.asc.ability_runtime.try_activate(baloo.granted[1])
	_check("and asking to activate it anyway says why", result.status == GameplayAbilityActivationResult.Status.INSUFFICIENT_RESOURCES, GameplayAbilityActivationResult.Status.keys()[result.status])
	var turns: int = await _act(baloo, 1, [dummy] as Array[Battler])
	_check("a turn spent on it ends at once", turns == 1, "%d" % turns)
	_check("and charges nothing, starts no cooldown, hurts nobody",
		is_equal_approx(baloo.attribute(BattlerAttributes.ENERGY), 0.0) and not baloo.asc.has_tag_exact(COOLDOWN) and is_equal_approx(_health(dummy), 100.0),
		"energy %.1f cooldown %s dummy %.1f" % [baloo.attribute(BattlerAttributes.ENERGY), baloo.asc.has_tag_exact(COOLDOWN), _health(dummy)])
	_finish("cost_refused")


func _case_cost_paid(baloo: Battler, dummy: Battler) -> void:
	baloo.asc.set_attribute_base(BattlerAttributes.ENERGY, 6.0)
	_check("with six energy, Punch may be used", _error(baloo, 1) == "NONE", _error(baloo, 1))
	await _act(baloo, 1, [dummy] as Array[Battler])
	_check("using it charges its three", is_equal_approx(baloo.attribute(BattlerAttributes.ENERGY), 3.0), "energy %.1f" % baloo.attribute(BattlerAttributes.ENERGY))
	_check("and puts it on cooldown for four turns", baloo.asc.has_tag_exact(COOLDOWN) and baloo.asc.get_tag_turns_remaining(COOLDOWN) == 4, "tag %s turns %d" % [baloo.asc.has_tag_exact(COOLDOWN), baloo.asc.get_tag_turns_remaining(COOLDOWN)])
	_check("where the engine refuses it for the cooldown", _error(baloo, 1) == "ON_COOLDOWN", _error(baloo, 1))
	_finish("cost_paid")


func _case_cooldown(baloo: Battler) -> void:
	baloo.asc.advance_turn(3)
	_check("three turns later it is still cooling down", baloo.asc.has_tag_exact(COOLDOWN) and _error(baloo, 1) == "ON_COOLDOWN", "turns left %d, %s" % [baloo.asc.get_tag_turns_remaining(COOLDOWN), _error(baloo, 1)])
	baloo.asc.advance_turn(1)
	_check("and on the fourth it lifts", not baloo.asc.has_tag_exact(COOLDOWN) and _error(baloo, 1) == "NONE", "tag %s, %s" % [baloo.asc.has_tag_exact(COOLDOWN), _error(baloo, 1)])
	_finish("cooldown")


func _case_energy_clamp(baloo: Battler) -> void:
	baloo.asc.set_attribute_base(BattlerAttributes.ENERGY, 5.0)
	baloo.asc.apply_gameplay_effect(_instant_add(BattlerAttributes.ENERGY, 1.0))
	baloo.asc.apply_gameplay_effect(_instant_add(BattlerAttributes.ENERGY, 1.0))
	_check("the round's energy tick stops at the maximum", is_equal_approx(baloo.attribute(BattlerAttributes.ENERGY), 6.0), "energy %.1f" % baloo.attribute(BattlerAttributes.ENERGY))
	_finish("energy_clamp")
#endregion


#region Buffs and bounds
func _case_buff(baloo: Battler) -> void:
	var before: Array[ActiveGameplayEffect] = baloo.asc.get_active_effects()
	await _act(baloo, 0, [baloo] as Array[Battler])
	await _act(baloo, 0, [baloo] as Array[Battler])
	_check("two Focus stack onto attack", is_equal_approx(baloo.attribute(BattlerAttributes.ATTACK), 30.0), "attack %.1f" % baloo.attribute(BattlerAttributes.ATTACK))
	_check("while hit chance stays at its ceiling", is_equal_approx(baloo.attribute(BattlerAttributes.HIT_CHANCE), 100.0), "hit %.1f" % baloo.attribute(BattlerAttributes.HIT_CHANCE))
	var added: Array[ActiveGameplayEffect] = []
	for active: ActiveGameplayEffect in baloo.asc.get_active_effects():
		if not before.has(active):
			added.append(active)
	_check("as two effects of their own", added.size() == 2, "%d" % added.size())
	if added.size() == 2:
		baloo.asc.remove_active_effect(added[0])
		_check("taking one away leaves the other's ten", is_equal_approx(baloo.attribute(BattlerAttributes.ATTACK), 20.0), "attack %.1f" % baloo.attribute(BattlerAttributes.ATTACK))
		baloo.asc.remove_active_effect(added[1])
	_check("and taking both away lands exactly on the base", is_equal_approx(baloo.attribute(BattlerAttributes.ATTACK), 10.0) and is_equal_approx(baloo.attribute(BattlerAttributes.HIT_CHANCE), 100.0), "attack %.1f hit %.1f" % [baloo.attribute(BattlerAttributes.ATTACK), baloo.attribute(BattlerAttributes.HIT_CHANCE)])
	_finish("buff")


func _case_hit_clamp(baloo: Battler) -> void:
	baloo.asc.set_attribute_base(BattlerAttributes.HIT_CHANCE, 95.0)
	var before: Array[ActiveGameplayEffect] = baloo.asc.get_active_effects()
	await _act(baloo, 0, [baloo] as Array[Battler])
	_check("Focus on 95 hit chance stops at 100", is_equal_approx(baloo.attribute(BattlerAttributes.HIT_CHANCE), 100.0), "hit %.1f" % baloo.attribute(BattlerAttributes.HIT_CHANCE))
	for active: ActiveGameplayEffect in baloo.asc.get_active_effects():
		if not before.has(active):
			baloo.asc.remove_active_effect(active)
	_check("and when it ends, the 95 comes back rather than the ceiling", is_equal_approx(baloo.attribute(BattlerAttributes.HIT_CHANCE), 95.0), "hit %.1f" % baloo.attribute(BattlerAttributes.HIT_CHANCE))
	_finish("hit_clamp")


## `battler_attributes.gd` says a max_health buff that expires cannot leave health
## standing above the ceiling it just lost. Measured, not taken on its word.
func _case_max_drop(twin: Battler) -> void:
	var raised: ActiveGameplayEffect = twin.asc.apply_gameplay_effect(_lasting_add(BattlerAttributes.MAX_HEALTH, 50.0))
	twin.asc.set_attribute_base(BattlerAttributes.HEALTH, 150.0)
	_check("with max health raised to 150, health may reach 150", is_equal_approx(_health(twin), 150.0), "health %.1f max %.1f" % [_health(twin), twin.attribute(BattlerAttributes.MAX_HEALTH)])
	if raised != null:
		twin.asc.remove_active_effect(raised)
	_check("when the raise ends, max health is 100 again", is_equal_approx(twin.attribute(BattlerAttributes.MAX_HEALTH), 100.0), "max %.1f" % twin.attribute(BattlerAttributes.MAX_HEALTH))
	_check("and health is not left standing above it", _health(twin) <= 100.0 + 0.001, "health %.1f, base %.1f" % [_health(twin), twin.asc.get_attribute_base(BattlerAttributes.HEALTH)])
	# The shown number is one half. A hit writes the base, and a base left above
	# the ceiling it lost is health nobody can see - the next blow spends it first.
	twin.asc.apply_gameplay_effect(_instant_add(BattlerAttributes.HEALTH, -30.0))
	_check("and the next hit of thirty takes thirty off what is shown", is_equal_approx(_health(twin), 70.0), "health %.1f, base %.1f" % [_health(twin), twin.asc.get_attribute_base(BattlerAttributes.HEALTH)])
	_finish("max_drop")
#endregion


#region Cancelling a swing
func _case_cancel_windup(wolf: Battler) -> void:
	Engine.time_scale = 1.0
	var victim: Battler = _spawn("WindupVictim", [], 600.0)
	await get_tree().process_frame
	_ability(wolf, 0).base_damage = 20.0
	var origin: Vector2 = wolf.position
	var turns: Array[int] = [0]
	wolf.turn_finished.connect(func _turned() -> void: turns[0] += 1)
	wolf.act(wolf.granted[0], [victim] as Array[Battler])
	wolf.asc.cancel_all_abilities()
	await _until(func _over() -> bool: return turns[0] > 0)
	await _settle(1.5)
	_check("a swing cancelled in its windup never lands", is_equal_approx(_health(victim), 100.0), "health %.1f" % _health(victim))
	_check("its turn still ends, once", turns[0] == 1, "%d" % turns[0])
	_check("and the caster is where it started", wolf.position.is_equal_approx(origin), "%s -> %s" % [origin, wolf.position])
	victim.free()
	_finish("cancel_windup")


func _case_cancel_travel(wolf: Battler) -> void:
	Engine.time_scale = 1.0
	var victim: Battler = _spawn("TravelVictim", [], 600.0)
	await get_tree().process_frame
	var origin: Vector2 = wolf.position
	var turns: Array[int] = [0]
	wolf.turn_finished.connect(func _turned() -> void: turns[0] += 1)
	wolf.act(wolf.granted[0], [victim] as Array[Battler])
	var moving: bool = await _until(func _left() -> bool: return wolf.position.distance_to(origin) > 20.0, 3.0)
	_check("the caster sets off toward its target", moving)
	wolf.asc.cancel_all_abilities()
	await _until(func _over() -> bool: return turns[0] > 0)
	await _settle(1.5)
	_check("a swing cancelled on its way never lands", is_equal_approx(_health(victim), 100.0), "health %.1f" % _health(victim))
	_check("its turn still ends, once", turns[0] == 1, "%d" % turns[0])
	_check("and the caster comes home rather than staying out there", wolf.position.distance_to(origin) < 1.0, "%s -> %s" % [origin, wolf.position])
	victim.free()
	_finish("cancel_travel")
#endregion
