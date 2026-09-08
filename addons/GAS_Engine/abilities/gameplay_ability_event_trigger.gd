## One entry in GameplayAbility.gameplay_event_triggers: an event tag pattern
## that wakes an ON_GAMEPLAY_EVENT ability.
##
## `event_query` is matched against a single-element tag set holding the
## dispatched event's own tag, so the same hierarchical rule
## GameplayTagQuery already implements (a listener on `Event.Damage` also
## hears `Event.Damage.Critical`) applies here for free, and an ability can
## declare more than one trigger without a second matching rule.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilityEventTrigger extends Resource

## What wakes this trigger.
##
## Three, matching the reference. The two tag sources are not the same
## question: OWNED_TAG_ADDED is an edge and OWNED_TAG_PRESENT is a level, so
## an ability that wants "while burning" answered by the edge would never
## start on a character that was already burning when it was granted.
enum Source {
	## An event was dispatched. The ability receives its payload.
	GAMEPLAY_EVENT,
	## The owner just acquired a matching tag. Losing it again does not
	## cancel what the acquisition started.
	OWNED_TAG_ADDED,
	## The owner has a matching tag now - including at the moment of the
	## grant. Losing it cancels the activation, because the tag is the
	## condition the ability runs under rather than the thing that started it.
	OWNED_TAG_PRESENT,
}

@export var source: GameplayAbilityEventTrigger.Source = Source.GAMEPLAY_EVENT
@export var event_query: GameplayTagQuery = null


## Convenience: an ANY-query for a single tag, behaving exactly like F2's
## singular trigger_event_tag did.
static func for_tag(tag: StringName) -> GameplayAbilityEventTrigger:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = [tag]
	var trigger: GameplayAbilityEventTrigger = GameplayAbilityEventTrigger.new()
	trigger.source = GameplayAbilityEventTrigger.Source.GAMEPLAY_EVENT
	trigger.event_query = GameplayTagQuery.new()
	trigger.event_query.root = expression
	return trigger
