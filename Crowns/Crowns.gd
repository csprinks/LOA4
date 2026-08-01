# Crowns.gd
extends Node

## Singleton for the party's shared currency (crowns).

var crowns: int = 0:
	set(value):
		var old = crowns
		crowns = value
		emit_signal("crowns_changed", old, crowns)

signal crowns_changed(old_amount, new_amount)


func add_crowns(amount: int) -> void:
	crowns += amount


func spend_crowns(amount: int) -> bool:
	if crowns >= amount:
		crowns -= amount
		return true
	return false


func get_crowns() -> int:
	return crowns
