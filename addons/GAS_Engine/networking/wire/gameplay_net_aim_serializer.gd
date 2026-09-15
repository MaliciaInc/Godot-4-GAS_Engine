## An aim onto a wire and back.
##
## Each hit is three flags - two dimensions or three, names somebody, knows
## where - followed only by what the flags said is there, in the shape the
## reference's hit result takes: flags first, then the fields they vouch for.
## A position crosses quantized to the centimetre and a normal as sixteen fixed
## bits a component, both by GameplayNetQuantize.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetAimSerializer extends RefCounted


static func write(writer: GameplayNetBitWriter, aim: GameplayNetAim) -> void:
	writer.write_count(aim.hits.size(), GameplayNetAim.MOST_HITS)
	for hit: GameplayNetAim.Hit in aim.hits:
		writer.write_bool(hit.is_two_d())
		writer.write_bool(hit.names_somebody())
		writer.write_bool(hit.has_position)
		if hit.names_somebody():
			writer.write_signed(hit.entity)
		if not hit.has_position:
			continue
		if hit.is_two_d():
			GameplayNetQuantize.write_position_2d(writer, hit.position_2d)
			GameplayNetQuantize.write_normal_2d(writer, hit.normal_2d)
		else:
			GameplayNetQuantize.write_position_3d(writer, hit.position_3d)
			GameplayNetQuantize.write_normal_3d(writer, hit.normal_3d)


## The aim back, or null with the reader failed.
static func read(reader: GameplayNetBitReader) -> GameplayNetAim:
	var made: GameplayNetAim = GameplayNetAim.new()
	var count: int = reader.read_count(GameplayNetAim.MOST_HITS)
	for _entry: int in count:
		var hit: GameplayNetAim.Hit = GameplayNetAim.Hit.new()
		var two_d: bool = reader.read_bool()
		var names_somebody: bool = reader.read_bool()
		hit.has_position = reader.read_bool()
		hit.space_kind = (
			GameplayTargetHit.SpaceKind.TWO_D if two_d else GameplayTargetHit.SpaceKind.THREE_D
		)
		if names_somebody:
			hit.entity = reader.read_signed()
			# A flag saying somebody was named, followed by the value that means
			# nobody, is not something a writer produces.
			if hit.entity == GameplayNetEntityId.NONE:
				reader.fail()
		if hit.has_position:
			if two_d:
				hit.position_2d = GameplayNetQuantize.read_position_2d(reader)
				hit.normal_2d = GameplayNetQuantize.read_normal_2d(reader)
			else:
				hit.position_3d = GameplayNetQuantize.read_position_3d(reader)
				hit.normal_3d = GameplayNetQuantize.read_normal_3d(reader)
		made.hits.append(hit)
	return made if reader.is_ok() else null
