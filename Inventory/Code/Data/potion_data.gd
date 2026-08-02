class_name PotionData
extends InventoryData

@export_enum("HEALTH", "MANA", "ACTION_POINTS", "ENERGY")
var potionType: int = PotionTypes.HEALTH

@export var amount: int = 0
