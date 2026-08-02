extends Node
# NOTE: no class_name here — "InventoryEvents" is already the name of this
# autoload singleton; Godot forbids a global class_name that matches an
# existing autoload name. Other scripts reference this one as a plain Node.

signal ShowInventory
signal ShowEquipment
signal ShowInspector(inspectorData: InspectorDataVariant)
signal CloseInspector
signal UseItem(data: UseItemData)

func EmitShowInventory() -> void:
	ShowInventory.emit()

func EmitShowEquipment() -> void:
	ShowEquipment.emit()

func EmitShowInspector(inspectorData: InspectorDataVariant) -> void:
	ShowInspector.emit(inspectorData)

func EmitCloseInspector() -> void:
	CloseInspector.emit()

func EmitUseItem(data: UseItemData) -> void:
	UseItem.emit(data)
