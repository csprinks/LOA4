class_name Potion
extends InventoryItem

var potionType: int = PotionTypes.HEALTH
var potionStrength: int = PotionStrengths.SMALL

var _inventoryEvents: Node
var spellEffectID: int
var SpellEffectID: int

func _init(initialPotionType: int = PotionTypes.HEALTH) -> void:
	potionType = initialPotionType

func SetInventoryEvents(inventoryEvents: Node) -> void:
	_inventoryEvents = inventoryEvents

func UseItem() -> void:
	var data := UseItemData.new()
	data.action = ActionTaken.USE_POTION
	data.item = self
	data.targets = []
	_inventoryEvents.EmitUseItem(data)
