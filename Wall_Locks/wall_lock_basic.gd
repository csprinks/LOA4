extends StaticBody3D

@export var target_door: DoorGrate

func _ready():
	add_to_group("interactable")

func interact():
	if target_door:
		target_door.activate()
		print("Button activated door: ", name)
