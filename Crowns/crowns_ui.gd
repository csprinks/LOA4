extends Control
class_name CrownsUI

## Displays the party's crown total, kept in sync with the Crowns singleton.

@export var crowns_label: Label

func _ready():
	if not Crowns.crowns_changed.is_connected(update_display):
		Crowns.crowns_changed.connect(update_display)

	# Show the current value immediately.
	update_display(0, Crowns.get_crowns())

	if not crowns_label:
		push_warning("CrownsUI: crowns_label not set!")

func update_display(_old_amount: int, new_amount: int):
	if crowns_label:
		crowns_label.text = str(new_amount)
