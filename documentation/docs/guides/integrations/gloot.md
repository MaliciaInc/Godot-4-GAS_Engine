---
title: GLoot
sidebar_position: 2
description: Granting abilities, passive effects and tags from equipped GLoot items with GlootGasBridge and an equipment catalog.
---

# GLoot

`GlootGasBridge` keeps an ability system in step with one GLoot item slot. Equipping an item grants what the catalog says that item gives; unequipping takes back exactly what was granted.

| | |
|---|---|
| Certified GLoot version | `v3.0.2` |
| Uses | An `ItemSlot`'s `item_equipped` and `cleared` signals, `get_item()`, and the item's prototype id |

## The equipment catalog

A `GlootGasEquipmentCatalog` lists what each item prototype grants:

| `GlootGasEquipmentGrant` field | Meaning |
|---|---|
| `prototype_id` | The GLoot prototype id this entry is for. |
| `abilities` | Ability scenes granted while the item is worn. |
| `passive_effects` | Effects applied while the item is worn. Each must be `INFINITE` and silent. |
| `direct_tags` | Tags added while the item is worn. |

**`res://game/equipment/weapon_catalog.gd`**

```gdscript
class_name WeaponCatalog extends RefCounted


static func weapons() -> GlootGasEquipmentCatalog:
	var sword: GlootGasEquipmentGrant = GlootGasEquipmentGrant.new()
	sword.prototype_id = &"iron_sword"
	sword.abilities = [preload("res://game/abilities/cleave.tscn")] as Array[PackedScene]
	sword.passive_effects = [preload("res://game/effects/sword_attack_bonus.tres")] as Array[GameplayEffect]
	sword.direct_tags = [&"Equipment.Weapon.Sword"] as Array[StringName]

	var catalog: GlootGasEquipmentCatalog = GlootGasEquipmentCatalog.new()
	catalog.grants = [sword] as Array[GlootGasEquipmentGrant]
	return catalog
```

A catalog with two entries for the same prototype id is refused when binding.

Passive effects must be `INFINITE` because they last exactly as long as the item is worn, and silent because equipping is all-or-nothing: a failed equip rolls back, and a cue that already played or an event already sent cannot be taken back.

## Binding a slot

```gdscript
@onready var weapon_slot: Node = $Inventory/WeaponSlot


func _ready() -> void:
	var bridge: GlootGasBridge = GlootGasBridge.new()
	add_child(bridge)
	bridge.equipment_rejected.connect(_on_equipment_rejected)
	if bridge.bind(weapon_slot, asc, WeaponCatalog.weapons()):
		bridge.refresh_from_slot()
```

| Method | Purpose |
|---|---|
| `bind(item_slot, asc, catalog)` | Listen to a slot. `false` when anything needed is missing, or the catalog is ambiguous. |
| `refresh_from_slot()` | Take back what is worn and grant what the slot holds now - for an item already equipped before binding. |
| `unbind()` | Stop listening and take back whatever the worn item granted. |

Bind one bridge per slot.

## What happens on equip

1. The prototype id is read from the item in the slot.
2. Every ability scene is validated before anything is granted.
3. Abilities are granted, effects applied and tags added. Abilities carry a `GameplayAbilityNamedSource` whose `id` is the prototype id.
4. If any step fails, what was already given is taken back.

| Signal | Emitted when |
|---|---|
| `equipment_applied(prototype_id)` | Everything was granted. |
| `equipment_removed(prototype_id)` | The item came off and its grant was taken back. |
| `equipment_rejected(prototype_id)` | The item is not in the catalog, its grant is invalid, or a step failed and was rolled back. |

Unequipping removes exactly what the equip recorded - the same handles and the same number of tag references - so a tag that a buff also grants stays held after the item comes off.
