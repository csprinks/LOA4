class_name FortunePoints
extends RefCounted

signal value_changed(new_value)

var current: int

func _init(initial_value: int = 1) -> void:
	current = initial_value

func set_current(value: int) -> void:
	current = max(0, value)
	value_changed.emit(current)

func reduce(amount: int) -> void:
	set_current(current - amount)

func increase(amount: int) -> void:
	set_current(current + amount)

func has_points(amount: int) -> bool:
	return current >= amount
