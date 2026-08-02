class_name InventoryData
extends Resource

@export var itemName: String = "Item Name"

@export var description: String = "Description Text"

@export var icon: Texture2D

@export var stackable: bool = false

# When true, the item gets procedurally rolled bonus attributes when created.
# Turn this off for hand-authored / fixed-stat items (e.g. specific chest loot)
# so every copy is identical and carries no random bonuses.
@export var randomizeAttributes: bool = true

@export_enum("NONE", "ARM", "CHEST", "EAR", "FEET", "HANDS", "HEAD", "LEGS", "NECK", "RING", "WRIST", "WEAPON_1H", "WEAPON_2H", "WEAPON_PRIMARY", "WEAPON_SECONDARY")
var thisSlotRequires: int = Requires.NONE

@export_enum("BLANK_ITEM", "ARMOR", "CONTAINER", "EQUIPMENT", "POTION", "SCROLL", "SPELL", "QUEST_ITEM", "WEAPON", "WORLD_ITEM")
var itemType: int = ItemTypes.BLANK_ITEM

@export_enum("COMMON", "RARE", "SUPERIOR", "ELITE")
var quality: int = ItemQuality.COMMON

@export var price: int = 1

@export var quantity: int = 1

@export var isBlank: bool = true
