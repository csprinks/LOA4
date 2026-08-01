class_name Armor
extends RefCounted

signal value_changed(new_value)

var value: int

func _init(initial_value: int = 0) -> void:
	value = initial_value

func set_value(new_value: int) -> void:
	value = max(0, new_value)
	value_changed.emit(value)

func increase(amount: int) -> void:
	set_value(value + amount)

func reduce(amount: int) -> void:
	set_value(max(0, value - amount))
