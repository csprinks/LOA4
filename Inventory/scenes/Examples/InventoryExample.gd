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

#region Persistence
# Snapshot every slot to a JSON-safe array aligned to slot order ({} for blanks),
# so item positions survive a save/load.
func serialize() -> Array:
	var out: Array = []
	for slot in inventory:
		if slot.IsBlank():
			out.append({})
		else:
			out.append(EquipmentSerializer.item_to_dict(slot.GetData()))
	return out

# Rebuild the backpack from a serialize() array, replacing whatever is there.
func deserialize(data: Array, events: Node) -> void:
	for i in range(inventory.size()):
		var slot := inventory[i]
		var dict = data[i] if i < data.size() else {}
		if dict is Dictionary and not dict.is_empty():
			var item := EquipmentSerializer.item_from_dict(dict, events)
			if item != null:
				slot.SetData(item)
				continue
		# Empty dict, out-of-range, or an item whose resource no longer exists.
		slot.SetData(slot.ClearData())

# Empty every slot (used when starting a new game).
func Clear() -> void:
	for slot in inventory:
		slot.SetData(slot.ClearData())
#endregion
