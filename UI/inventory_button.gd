extends TextureButton

var InventoryEvents

func _ready():
	InventoryEvents = get_node("/root/InventoryEvents")
	pressed.connect(_button_pressed)

func _input(event):
	# Handle 'I' key press to toggle the inventory screen
	if event.is_action_pressed("inventory_screen") or (event is InputEventKey and event.pressed and event.keycode == KEY_I):
		InventoryEvents.EmitShowInventory()
		get_viewport().set_input_as_handled()

func _button_pressed():
	InventoryEvents.EmitShowInventory()
