## One refused GameplayEffect application, as GameplayEffectRefusalLog keeps
## it - the same GameplayEffectApplicationResult apply() already returns to
## its caller, so every refusal reason apply() can produce (invalid spec,
## chain depth, immunity, a component's application query or custom
## requirement, stack overflow, or an evaluator failure with its own
## finer-grained status) is one closed type, never a second vocabulary.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectRefusalRecord extends RefCounted

var result: GameplayEffectApplicationResult = null

## Monotonic order among refusals this log has ever recorded - stable even
## after older entries age out of the ring buffer.
var order: int = 0
