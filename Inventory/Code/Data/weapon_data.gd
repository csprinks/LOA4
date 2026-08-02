class_name WeaponData
extends InventoryData

@export_enum("SHIELD", "ONE_HAND", "ONE_HAND_PRIMARY", "TWO_HAND", "POLEARM", "DAGGER", "STAFF", "BOW")
var weaponType: int = WeaponTypes.SHIELD

@export var minDamage: int = 0

@export var maxDamage: int = 0

@export var isRanged: bool = false

@export var ActionPointCost: int = 0
