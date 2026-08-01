class_name HitPoints
extends RefCounted

signal value_changed(new_value)
signal max_changed(new_max)

var current: int
var max_value: int

func _init(initial_max: int = 100) -> void:
	max_value = initial_max
	current = max_value

func set_current(value: int) -> void:
	current = clampi(value, 0, max_value)
	value_changed.emit(current)

func set_max(value: int) -> void:
	max_value = max(0, value)
	current = min(current, max_value)
	max_changed.emit(max_value)

func reduce(amount: int) -> void:
	set_current(current - amount)

func increase(amount: int) -> void:
	set_current(current + amount)

func reset() -> void:
	set_current(max_value)

func get_percentage() -> float:
	return float(current) / float(max_value) if max_value > 0 else 0.0
