## A whole aim, authored as a list of steps.
##
## "Everything within five metres, that is an enemy, nearest first, first three"
## is four steps and no script. Each one is handed what the last one found, in
## the order they were authored, and the answer is whatever the last one hands
## back.
##
## In order and nothing else. No concurrency, because two steps running at once
## would answer differently depending on which finished first; no implicit
## random, because a preset that answered differently on two machines could not
## be checked by either of them.
##
## Local authoring. A preset never crosses a wire - what crosses is the target
## data it produced, which the server checks against the aim it would have
## produced itself.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTargetingPreset extends Resource

@export var tasks: Array[GameplayTargetingTask] = []


## Run every step, in the order they are written.
##
## Starts from an empty aim rather than from null, so the first step is handed
## the same kind of thing every other step is - a selecting step that had to
## handle null as well as empty would be handling two spellings of nothing.
## @composer
func execute(source_asc: AbilitySystemComponent) -> GameplayAbilityTargetData:
	var carried: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	for task: GameplayTargetingTask in tasks:
		if task == null:
			continue
		var produced: GameplayAbilityTargetData = task.execute(carried, source_asc)
		# A step that answered with nothing at all is a step that answered
		# nothing: carrying null forward would make every later step check for
		# it, and dropping the aim would lose what the earlier ones found.
		if produced != null:
			carried = produced
	return carried
