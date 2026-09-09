## One rule about a kind of ability, written once instead of on every ability it
## happens to be about.
##
## A growing ruleset finds this out the hard way: the fourteenth ability is the
## one that forgot the rule the other thirteen have. A row here says it once -
## "anything that is a melee attack is blocked while stunned" - and the fourteenth
## is covered by being what it is.
##
## Rules only ever add. A row cannot make an ability activatable that its own
## declaration refused, because a central table quietly overruling what an ability
## says about itself is a rule nobody reading the ability could account for.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilityTagRelationship extends Resource

## Which abilities this row is about, matched against their effective tags.
@export var ability_query: GameplayTagQuery = null

## While one of them runs, abilities matching this are refused.
@export var blocks_query: GameplayTagQuery = null

## Starting one of them cancels abilities matching this.
@export var cancels_query: GameplayTagQuery = null

## They cannot start unless the owner's tags match this.
@export var requires_query: GameplayTagQuery = null

## They cannot start while the owner's tags match this.
@export var blocked_by_query: GameplayTagQuery = null
