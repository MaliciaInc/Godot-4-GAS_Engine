## One entry in GameplayAbility.gameplay_event_triggers: an event tag pattern
## that wakes an ON_GAMEPLAY_EVENT ability.
##
## `event_query` is matched against a single-element tag set holding the
## dispatched event's own tag, so the same hierarchical rule
## GameplayTagQuery already implements (a listener on `Event.Damage` also
## hears `Event.Damage.Critical`) applies here for free, and an ability can
## declare more than one trigger without a second matching rule.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayAbilityEventTrigger extends Resource

@export var event_query: GameplayTagQuery = null


## Convenience: an ANY-query for a single tag, behaving exactly like F2's
## singular trigger_event_tag did.
static func for_tag(tag: StringName) -> GameplayAbilityEventTrigger:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = [tag]
	var trigger: GameplayAbilityEventTrigger = GameplayAbilityEventTrigger.new()
	trigger.event_query = GameplayTagQuery.new()
	trigger.event_query.root = expression
	return trigger
