class_name Stat
extends RefCounted

## Base class for a single character stat (Might, Awareness, Finesse, Intellect,
## Charm, Fate). Each stat starts at a base value and is raised by spending
## Attribute Points; every point adds `gain_per_point` (set by the character's
## class relationship at creation). Subclasses exist so per-stat behaviour can be
## added later.

signal changed(new_total: int)

const BASE_DEFAULT := 10

var base: int = BASE_DEFAULT
var points_spent: int = 0
var gain_per_point: int = 1

# Base + (Attribute Points spent * gain per point).
var total: int:
	get: return base + points_spent * gain_per_point

func _init(base_value: int = BASE_DEFAULT, points: int = 0, gain: int = 1) -> void:
	base = base_value
	points_spent = points
	gain_per_point = gain

func configure(base_value: int, points: int, gain: int) -> void:
	base = base_value
	points_spent = points
	gain_per_point = gain
	changed.emit(total)

func to_dict() -> Dictionary:
	return {
		"base": base,
		"points_spent": points_spent,
		"gain_per_point": gain_per_point,
	}

func from_dict(data: Dictionary) -> void:
	base = int(data.get("base", BASE_DEFAULT))
	# Fall back to the pre-rename keys so old save files still load.
	points_spent = int(data.get("points_spent", data.get("deeds_spent", 0)))
	gain_per_point = int(data.get("gain_per_point", data.get("points_per_deed", 1)))
	changed.emit(total)
