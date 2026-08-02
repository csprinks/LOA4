class_name InventoryExample
extends CanvasLayer

@export var inventoryPanel: Panel
@export var inventoryGridContainer: GridContainer

var inventory: Array[InventoryContainer] = []

func _ready() -> void:
	for child in inventoryGridContainer.get_children():
		if child is InventoryContainer:
			inventory.append(child)

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
