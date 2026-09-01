## Who is in this fight, and on which side.
##
## The roster answers questions about sides and about who is still standing.
## It deliberately does not answer "whose turn is it" or "has this one chosen
## yet": a turn is a thing the arena runs, and a roster that also tracked turn
## intent would be a second place for the fight's state to live.
##
## @meta_license: MIT
@icon("icon_turn_queue.png")
class_name BattlerRoster extends Node


func get_battlers() -> Array[Battler]:
	var battler_list: Array[Battler] = []
	battler_list.assign(find_children("*", "Battler"))
	return battler_list


func get_player_battlers() -> Array[Battler]:
	return get_battlers().filter(
		func _filter_players(battler: Battler) -> bool:
			return battler.is_player
	)


func get_enemy_battlers() -> Array[Battler]:
	return get_battlers().filter(
		func _filter_enemies(battler: Battler) -> bool:
			return not battler.is_player
	)


## Everyone still in the fight.
##
## Asked of the battler, which asks its component - never of a health number
## read from somewhere else. `State.Downed` goes on before anything is told a
## battler fell, so this can never report someone as standing who is already out.
func get_standing(side: Array[Battler]) -> Array[Battler]:
	return side.filter(
		func _filter_standing(battler: Battler) -> bool:
			return not battler.is_downed()
	)


## True once one whole side is out.
func is_side_defeated(side: Array[Battler]) -> bool:
	return get_standing(side).is_empty()


## Turn order, fastest first. Read live from each battler's `speed`, so a haste
## effect applied this round is felt in the next ordering rather than at reload.
func in_turn_order() -> Array[Battler]:
	var ordered: Array[Battler] = get_standing(get_battlers())
	ordered.sort_custom(Battler.sort_by_speed)
	return ordered


func _to_string() -> String:
	var msg: String = "\n%s - BattlerRoster" % name
	for battler: Battler in in_turn_order():
		msg += "\n\t%s%s" % [battler.name, " - DOWNED" if battler.is_downed() else ""]
	return msg
