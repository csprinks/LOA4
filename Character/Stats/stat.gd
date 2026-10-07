class_name Stat
extends RefCounted

## Base class for a single character stat (Might, Awareness, Finesse, Intellect,
## Charm, Fate). Each stat is a base value plus a bonus from the skills owned in
## its skill line; the bonus is derived (Character.refresh_stat_bonuses), never
## saved. Subclasses exist so per-stat behaviour can be added later.

signal changed(new_total: int)

const BASE_DEFAULT := 10

var base: int = BASE_DEFAULT
var bonus: int = 0

var total: int:
	get: return base + bonus

func _init(base_value: int = BASE_DEFAULT) -> void:
	base = base_value

func set_bonus(value: int) -> void:
	bonus = value
	changed.emit(total)

func to_dict() -> Dictionary:
	return {"base": base}

func from_dict(data: Dictionary) -> void:
	base = int(data.get("base", BASE_DEFAULT))
	changed.emit(total)
