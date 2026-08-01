class_name Stat
extends RefCounted

## Base class for a single character stat (Might, Awareness, Finesse, Intellect,
## Charm, Fate). Each stat starts at a base value and is raised by spending Deed
## Points; every Deed adds `points_per_deed` (set by the character's class
## relationship at creation). Subclasses exist so per-stat behaviour can be
## added later.

signal changed(new_total: int)

const BASE_DEFAULT := 10

var base: int = BASE_DEFAULT
var deeds_spent: int = 0
var points_per_deed: int = 1

# Base + (Deeds spent * points per Deed).
var total: int:
	get: return base + deeds_spent * points_per_deed

func _init(base_value: int = BASE_DEFAULT, deeds: int = 0, ppd: int = 1) -> void:
	base = base_value
	deeds_spent = deeds
	points_per_deed = ppd

func configure(base_value: int, deeds: int, ppd: int) -> void:
	base = base_value
	deeds_spent = deeds
	points_per_deed = ppd
	changed.emit(total)

func to_dict() -> Dictionary:
	return {
		"base": base,
		"deeds_spent": deeds_spent,
		"points_per_deed": points_per_deed,
	}

func from_dict(data: Dictionary) -> void:
	base = int(data.get("base", BASE_DEFAULT))
	deeds_spent = int(data.get("deeds_spent", 0))
	points_per_deed = int(data.get("points_per_deed", 1))
	changed.emit(total)
