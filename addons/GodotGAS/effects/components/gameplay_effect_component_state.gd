## Base for one component's runtime state, scoped to exactly one application.
##
## A GameplayEffectComponent is immutable authored data - none of Task 8's
## six concrete components need any state of their own. This class exists so
## a future component that DOES (Task 14's PreparedAbilityGrant, say) has
## somewhere typed to put it, tracked by GameplayEffectSpec and
## ActiveGameplayEffect by component index, never by Resource identity.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectComponentState extends RefCounted
