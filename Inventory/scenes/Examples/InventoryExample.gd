class_name InventoryExample
extends CanvasLayer

@export var inventoryPanel: Panel
@export var inventoryGridContainer: GridContainer
## Optional in-inventory button that opens the in-game system menu (Save/Load/
## Options/Quit). Wired through InventoryEvents so this widget stays decoupled.
@export var menuButton: Button

var inventory: Array[InventoryContainer] = []

func _ready() -> void:
	for child in inventoryGridContainer.get_children():
		if child is InventoryContainer:
			inventory.append(child)

	if menuButton:
		menuButton.pressed.connect(_on_menu_button_pressed)

func _on_menu_button_pressed() -> void:
	var events := get_node_or_null("/root/InventoryEvents")
	if events:
		events.EmitShowSystemMenu()

func ShowInventory() -> void:
	inventoryPanel.visible = not inventoryPanel.visible

func LoadItems(items: Array) -> void:
	var emptySlots: Array[InventoryContainer] = []
	for slot in inventory:
		if slot.IsBlank():
			emptySlots.append(slot)

	for item in items:
		if emptySlots.size() > 0:
			emptySlots[0].SetData(item)
			emptySlots.remove_at(0)

# Place a single item into the first available blank slot at runtime.
# Returns false if the inventory is full (no blank slots remain).
func AddItem(item: InventoryItem) -> bool:
	for slot in inventory:
		if slot.IsBlank():
			slot.SetData(item)
			return true
	return false
