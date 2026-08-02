class_name InventoryWeapon
extends InventoryItem

var weaponType: int = WeaponTypes.SHIELD
var weaponDamage: float = 1.0
var weaponSpeed: float = 1.0

var DPS: float:
	get:
		return 0.0 if weaponSpeed <= 0 else weaponDamage * weaponSpeed

var twoHanded: bool = false

var _inventoryEvents: Node

func SetInventoryEvents(inventoryEvents: Node) -> void:
	_inventoryEvents = inventoryEvents

func UseItem() -> void:
	Attack()

func Attack() -> void:
	var data := UseItemData.new()
	data.action = ActionTaken.ATTACK
	data.item = self
	data.targets = []
	_inventoryEvents.EmitUseItem(data)

func GetRequiredSlot(type: int) -> int:
	match type:
		WeaponTypes.SHIELD:
			return Requires.WEAPON_SECONDARY
		WeaponTypes.TWO_HAND, WeaponTypes.POLEARM, WeaponTypes.STAFF, WeaponTypes.BOW:
			return Requires.WEAPON_2H
		_:
			return Requires.WEAPON_PRIMARY

func GetDisplayName(type: int) -> String:
	match type:
		WeaponTypes.SHIELD: return "Shield - Secondary Only"
		WeaponTypes.ONE_HAND: return "One handed (1H)"
		WeaponTypes.ONE_HAND_PRIMARY: return "One handed (1H) - Primary Only"
		WeaponTypes.TWO_HAND: return "Two handed (2H)"
		WeaponTypes.POLEARM: return "Polearm (2H)"
		WeaponTypes.DAGGER: return "Dagger"
		WeaponTypes.STAFF: return "Staff (2H)"
		WeaponTypes.BOW: return "Bow (2H)"
		_: return "Weapon"
