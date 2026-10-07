extends StaticBody3D

@export var target_door: DoorGrate
## The item the party must be carrying to turn the lock. Empty = no key needed.
@export var required_key: InventoryData = preload("res://Keys/brass_key.tres")

func _ready():
	add_to_group("interactable")

func interact():
	if target_door == null:
		return
	if required_key and not InventoryManager.HasItem(required_key):
		ResourceManager.display_text("It is locked. You need the %s." % required_key.itemName)
		return
	target_door.activate()
