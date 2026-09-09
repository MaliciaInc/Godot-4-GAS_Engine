## Who is allowed to do what, said once and asked everywhere.
##
## The rules are short and the reason they live in one place is that they are
## the same rules on both machines. A client refusing to send what it may not
## send and an authority refusing to act on what it should not have received
## are two halves of one statement, and two copies of one statement is one of
## them being relaxed later by somebody who only had the other in front of them.
##
## Nothing here touches state. Every function answers a question about a role,
## a policy and an ownership, so the decisions can be read - and tested - by
## themselves, and the runtime that acts on them has no rules of its own.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetAuthority extends RefCounted

## Which machine this is.
##
## Two values and not three: a listen server is an authority that also has a
## local player, which is a fact about who owns an entity rather than about
## what the machine is allowed to do.
enum Role { AUTHORITY, CLIENT }

## The kinds that travel from a client towards the authority, and never back.
##
## A list rather than one name, because F6.6 gave a client five more things it
## may ask for and a rule written as "everything except the request" would have
## let each of them travel in both directions - which for a confirm is one
## machine cancelling another's ability.
##
## A batch is in neither: it is a wrapper, and what may travel is decided for
## each message inside it.
const ASKED_OF_THE_AUTHORITY: Array[GameplayNetMessage.Kind] = [
	GameplayNetMessage.Kind.ACTIVATION_REQUEST,
	GameplayNetMessage.Kind.TARGET_DATA,
	GameplayNetMessage.Kind.GENERIC_CONFIRM,
	GameplayNetMessage.Kind.GENERIC_CANCEL,
	GameplayNetMessage.Kind.INPUT_PRESSED,
	GameplayNetMessage.Kind.INPUT_RELEASED,
]

## The kinds that travel in either direction.
##
## An event is a notification rather than a request: an authority telling
## clients that something happened and a client telling the authority that
## something did are both ordinary, and a rule that picked one would make the
## other impossible to express. A batch is a wrapper, and what may travel is
## decided for each message inside it.
const EITHER_WAY: Array[GameplayNetMessage.Kind] = [
	GameplayNetMessage.Kind.GAMEPLAY_EVENT,
	GameplayNetMessage.Kind.BATCH,
]

## How a machine may start an ability, given the policy on its grant.
##
## RUN_NOW: run it here and tell nobody, because nobody else is involved.
## PREDICT_AND_ASK: run it here now and ask; a refusal is reversed.
## ASK_AND_WAIT: ask, and let nothing happen here until the answer comes.
## REFUSED: this machine may not start this ability at all.
enum Start { RUN_NOW, PREDICT_AND_ASK, ASK_AND_WAIT, REFUSED }


## What the owning client may do with an ability granted under this policy.
##
## This is the whole of what the four policy values mean from a client's side,
## and it is why they are four rather than two: the difference between
## LOCAL_PREDICTED and SERVER_INITIATED is not what is allowed but what happens
## while the answer is in flight.
static func client_start(policy: GameplayAbility.NetExecutionPolicy) -> GameplayNetAuthority.Start:
	match policy:
		GameplayAbility.NetExecutionPolicy.LOCAL_ONLY:
			return Start.RUN_NOW
		GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED:
			return Start.PREDICT_AND_ASK
		GameplayAbility.NetExecutionPolicy.SERVER_INITIATED:
			return Start.ASK_AND_WAIT
		_:
			return Start.REFUSED


## And what the authority may do, which is run it.
##
## Every policy answers RUN_NOW here, and that is not a shortcut: the authority
## is the machine whose answer is the answer, so there is nobody for it to ask
## and nothing for it to predict. LOCAL_ONLY included - an ability nobody else
## is told about still runs on the machine that owns the character.
static func authority_start(_policy: GameplayAbility.NetExecutionPolicy) -> GameplayNetAuthority.Start:
	return Start.RUN_NOW


## Whether a machine in this role may act on a message that arrived.
##
## The direction of a message is part of what it is. A client receiving a
## request to activate is a client being asked to be the authority; an
## authority receiving a grant is an authority being told what it granted. Both
## are somebody trying to be the other, and neither is a thing to act on.
static func accepts(role: GameplayNetAuthority.Role, message: GameplayNetMessage) -> bool:
	if message == null or not message.is_complete():
		return false
	if EITHER_WAY.has(message.kind):
		return true
	if role == Role.AUTHORITY:
		return ASKED_OF_THE_AUTHORITY.has(message.kind)
	return not ASKED_OF_THE_AUTHORITY.has(message.kind)


## Whether the authority should act on a request that arrived from a peer.
##
## Two questions in one because they are always asked together and refusing
## either means the same thing. Does the asker own the character it is asking
## about - a client may act for its own and for nobody else's - and is this an
## ability a client is allowed to ask for at all.
static func honours_request(
	owns_the_entity: bool, policy: GameplayAbility.NetExecutionPolicy
) -> bool:
	return owns_the_entity and client_start(policy) != Start.REFUSED


## Whether a machine in this role may write state of its own accord.
##
## The one rule underneath every other: a client does not author. It asks, it
## is told, and it predicts what it will be told - but a grant it wrote itself,
## an effect it applied on its own authority, an id it made up are all the same
## bug wearing different clothes, and it is the bug where a player gives
## themselves an ability.
static func may_author(role: GameplayNetAuthority.Role) -> bool:
	return role == Role.AUTHORITY
