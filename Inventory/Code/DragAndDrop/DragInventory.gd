class_name DragInventory
extends Control

var _inventoryManager: Node
@export var _defaultColor: Color = Color(1, 1, 1, 1)

signal DragCompleted(item: InventoryData)

var source: Control
var target: Control

var container: InventoryContainer
var preview: Control

func _ready() -> void:
	_inventoryManager = get_node("/root/InventoryManager")

func Init(sourceControl: Control, targetControl: Control, item: InventoryContainer, previewControl: Control) -> void:
	source = sourceControl
	target = targetControl
	container = item
	preview = previewControl

	preview.tree_exiting.connect(OnTreeExiting)

func OnTreeExiting() -> void:
	container.SetColor(_defaultColor)
	DragCompleted.emit(container)
