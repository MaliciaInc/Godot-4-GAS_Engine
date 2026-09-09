## The sample, run as a client, in a process of its own.
##
##     godot --headless --path . -s res://examples/action_sample/network/client_main.gd \
##         -- --client=127.0.0.1:47921 --automation --out=user://client.json
##
## The half that guesses. It predicts a strike and is told yes, aims a slam and
## sends where it aimed, predicts a channel and is told no - and the last of
## those is the one worth watching, because being told no is when a predicting
## client either puts back what it spent or quietly keeps it.
##
## Fourteen steps in order, each one waiting for the thing before it rather than
## for a number of frames. A scenario that waits for frames passes on a fast
## machine and fails on a busy one, which is indistinguishable from a bug.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
extends SceneTree

## What the refused guess spends before it is refused, so putting it back is
## visible rather than a subtraction of nothing.
const GUESSED_COST: float = 12.0

## Where the slam is aimed. Beside the first dummy, so the authority's own
## preset has somebody to pick.
const AIMED_AT: Vector3 = Vector3(3.0, 0.0, 0.0)

## What this process is waiting for.
enum Step {
	CONNECTING,
	GRANTS,
	FIRST_READING,
	STRIKE_ANSWER,
	AIM_ANSWER,
	REFUSAL,
	CLOSING_READING,
	DONE,
}

var session: SampleNetSession = null
var options: SampleNetOptions = null

var step: Step = Step.CONNECTING
var granted: int = 0

## The last reading this process was told, which is what it converged on.
var _last_reading: GameplayNetState = null
var _readings: int = 0
var _readings_at_settle: int = 0
var _mana_before_the_guess: float = 0.0


## Nothing but the arguments, because there is no tree yet.
##
## A SceneTree script runs before its own tree does, and a component that was
## never in a tree is one whose runtimes are still null. The standing happens on
## the first tick instead.
func _initialize() -> void:
	options = SampleNetOptions.read()


func _process(delta: float) -> bool:
	if session == null:
		return _stand()
	if step == Step.DONE:
		return true
	if session.out_of_patience(delta):
		_stop("stuck at %s after %.0f seconds" % [
			Step.keys()[step], SampleNetSession.PATIENCE_SECONDS
		])
		return true
	return false


func _finalize() -> void:
	if session != null:
		session.close()


## Build the world and start connecting. Answers whether to stop already.
func _stand() -> bool:
	session = SampleNetSession.standing(self, GameplayNetAuthority.Role.CLIENT)
	if not options.is_client:
		_stop("this is the client's entry point; it was asked for %s" % options.spelling())
		return true
	if not session.open(false, options.address, options.port):
		_stop(session.fault)
		return true

	session.say("connecting to %s:%d" % [options.address, options.port])
	session.api.connected_to_server.connect(_on_connected)
	session.api.connection_failed.connect(_on_connection_failed)
	session.network.ability_granted_by_authority.connect(_on_granted)
	session.network.activation_answered.connect(_on_answered)
	session.network.state_applied.connect(_on_state)
	session.complain()
	return false


#region The fourteen steps, in the order they happen
## Connected. Bind this machine's hero to the id the authority uses.
func _on_connected() -> void:
	# The id is assigned by the connection rather than by asking for one, so it
	# is read here and not when the peer was created: a client that attached
	# under the id it had before connecting would be asking for a character
	# nobody owns.
	session.network.peer = session.api.get_unique_id()
	session.attach(session.network.peer)
	step = Step.GRANTS
	session.say("connected as peer %d" % session.network.peer)


func _on_connection_failed() -> void:
	_stop("the authority did not answer on %s:%d" % [options.address, options.port])


## Every grant the authority made. The client is told rather than telling.
func _on_granted(_entity: GameplayNetEntityId, _definition: Resource) -> void:
	granted += 1
	if step == Step.GRANTS and granted >= session.world.hero.asc.get_ability_specs().size():
		step = Step.FIRST_READING
		session.say("told about %d grants" % granted)


## A reading arrived. The first one starts the scenario; the last one ends it.
func _on_state(_entity: GameplayNetEntityId, state: GameplayNetState) -> void:
	_last_reading = state
	_readings += 1
	if step == Step.FIRST_READING:
		session.say("read the opening state")
		_strike()
	elif step == Step.CLOSING_READING and _readings > _readings_at_settle:
		session.say("read the closing state")
		_finish()


## Predict a strike: run it here, and ask.
##
## Both, and in that order, because that is what predicting is. The runtime
## says what this machine may do about an ability and sends the asking; the
## game does the thing. A game that only asked would be a game where nothing
## happens until the round trip is over, which is what predicting is for.
func _strike() -> void:
	var scene: Resource = session.definition_tagged(SampleBasicAttack.TAG)
	var decided: GameplayNetAuthority.Start = session.network.start(
		session.world.hero.asc, scene
	)
	session.world.hero.strike(session.world.dummies[0])
	step = Step.STRIKE_ANSWER
	session.say("predicted a strike (%s) and asked" % GameplayNetAuthority.Start.keys()[decided])


## Aim the slam, and send where it was aimed.
##
## The aim travels as target data rather than as an activation with a position
## in it: the authority has its own provider waiting, and what it validates is
## the spot against that provider rather than a number a client attached to a
## request.
func _aim() -> void:
	var scene: Resource = session.definition_tagged(SampleGroundSlam.TAG)
	session.network.start(session.world.hero.asc, scene)
	session.world.hero.aim_slam()

	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	data.append_location(AIMED_AT)
	session.network.send_target_data(
		GameplayNetEntityId.of(SampleNetSession.HERO), data
	)
	step = Step.AIM_ANSWER
	session.say("aimed the slam at %v and sent it" % AIMED_AT)


## Predict something this client is not allowed to start, and spend on it.
##
## The channel's security policy reserves starting it to the authority. The
## client does not know that and does not have to: it guesses, spends what the
## guess would cost, and the answer comes back no. What is being checked is
## what happens next.
func _guess_wrong() -> void:
	var scene: Resource = session.definition_tagged(SampleChannel.TAG)
	session.network.start(session.world.hero.asc, scene)

	var asc: AbilitySystemComponent = session.world.hero.asc
	_mana_before_the_guess = asc.get_attribute_base(SampleAttributes.MANA)
	asc.set_attribute_base(SampleAttributes.MANA, _mana_before_the_guess - GUESSED_COST)
	# No key on the operation: `start` opened the window for the guess it just
	# made, and this is what a window is for.
	session.network.journal.record(
		GameplayPredictionOperation.cost(null, SampleAttributes.MANA, GUESSED_COST)
	)
	step = Step.REFUSAL
	session.say("predicted a channel and spent %.0f mana on it" % GUESSED_COST)


## The authority answered one of the guesses.
func _on_answered(
	_key: GameplayPredictionKey, _activation: GameplayNetActivationId, accepted: bool
) -> void:
	match step:
		Step.STRIKE_ANSWER:
			_after_strike(accepted)
		Step.AIM_ANSWER:
			_after_aim(accepted)
		Step.REFUSAL:
			_after_refusal(accepted)
		_:
			pass


func _after_strike(accepted: bool) -> void:
	if not accepted:
		_stop("the strike was refused, and it is the one that should not be")
		return
	session.say("the strike was accepted")
	_aim()


func _after_aim(accepted: bool) -> void:
	if not accepted:
		_stop("the aim was refused")
		return
	session.say("the aim was accepted and validated")
	_guess_wrong()


## Refused, which is the point. What matters is that the spending went back.
func _after_refusal(accepted: bool) -> void:
	if accepted:
		_stop("the channel was accepted, and only the authority may start it")
		return
	var now: float = session.world.hero.asc.get_attribute_base(SampleAttributes.MANA)
	if not is_equal_approx(now, _mana_before_the_guess):
		_stop("the refusal left %.1f mana spent" % (_mana_before_the_guess - now))
		return
	session.say("the channel was refused and the %.0f mana went back" % GUESSED_COST)
	_settle()


## Say there is nothing left to do, and wait for the reading that follows it.
func _settle() -> void:
	_readings_at_settle = _readings
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = SampleNetSession.SETTLED
	session.network.send_gameplay_event(
		GameplayNetEntityId.of(SampleNetSession.HERO), event
	)
	step = Step.CLOSING_READING
	session.say("settled")
#endregion


#region Ending
func _finish() -> void:
	step = Step.DONE
	session.report(options.out, SampleNetSession.fingerprint(_last_reading))


func _stop(why: String) -> void:
	session.stopping(why)
	session.report(options.out, SampleNetSession.fingerprint(_last_reading))
	step = Step.DONE
	quit(1)
#endregion
