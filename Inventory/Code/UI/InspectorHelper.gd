class_name InspectorHelper
extends CanvasLayer

@export var panelContainer: PanelContainer
@export var inspectorYOffset: int = 100

var itemTextPrefab: PackedScene
var attributeScrollViewParent: PackedScene
var _inspectorItem: InventoryItem
var _inspectorBaseInventory: InventoryItem

@export var commonQualityColor: Color = Color(50, 50, 50, 1)
@export var rareQualityColor: Color = Color(0, 255, 0, 1)
@export var superiorQualityColor: Color = Color(0, 0, 255)
@export var eliteQualityColor: Color = Color(153, 51, 255, 1)

@export var itemImage: TextureRect
@export var itemName: Label
@export var itemType: Label

var _statList: Array[PackedScene] = []
@export var itemArmor: Label
@export var itemValue: Label
@export var chargesValue: Label

@export var attribute_one: Label
@export var attribute_two: Label
@export var attribute_three: Label

func ShowInspector() -> void:
	panelContainer.visible = not panelContainer.visible

func CloseInspector() -> void:
	panelContainer.visible = false

func SetData(inspectorData: InspectorDataVariant) -> void:
	if inspectorData == null or inspectorData.item._resourceData.isBlank:
		return

	ShowInspectorItem(inspectorData.item)
	SetInspectorPosition(inspectorData.mousePosition)

func SetInspectorPosition(pointerPosition: Vector2) -> void:
	var screenSize = DisplayServer.window_get_size()
	var middle = float(screenSize.x) / 2.0

	var xPosition = 0.0
	if pointerPosition.x < middle:
		xPosition = middle

	panelContainer.position = Vector2(xPosition + 50, screenSize.y / 2.0 - inspectorYOffset)

func ShowInspectorItem(inventoryitem: InventoryItem) -> void:
	print("Showing inspector for item %s" % inventoryitem.itemName)
	var item = inventoryitem._resourceData

	itemName.modulate = GetColorForQuality(item.quality)
	itemName.text = item.itemName
	itemImage.texture = item.icon
	itemType.text = GetItemTypeText(item)

	if item.itemType == ItemTypes.ARMOR:
		var armor := item as ArmorData
		itemArmor.text = "Armor : %s" % (str(armor.armorAmount) if armor else "")
	else:
		itemArmor.text = ""

	itemValue.text = "Value : %s" % str(item.price)
	var chargeCount = inventoryitem.charges
	var chargesText = ("Charges : %s" % str(inventoryitem.charges)) if chargeCount > 0 else ""
	chargesValue.text = chargesText
	SetAttributes(inventoryitem)

func GetItemTypeText(item: InventoryData) -> String:
	match item.itemType:
		ItemTypes.EQUIPMENT:
			return GetNameForSlot(item.thisSlotRequires)
		ItemTypes.WEAPON:
			return GetWeaponItemTypeText(item.thisSlotRequires)
		ItemTypes.SCROLL:
			return "Scroll"
		ItemTypes.POTION:
			return "Potion"
		ItemTypes.CONTAINER:
			return "Container"
		ItemTypes.QUEST_ITEM:
			return "Quest Item"
		ItemTypes.SPELL:
			return "Spell"
		ItemTypes.BLANK_ITEM:
			return ""
		ItemTypes.WORLD_ITEM:
			return ""
		_:
			return ""

func GetWeaponItemTypeText(requirement: int) -> String:
	match requirement:
		Requires.WEAPON_1H:
			return "Weapon (1H)"
		Requires.WEAPON_2H:
			return "Weapon (2H)"
		Requires.WEAPON_PRIMARY:
			return "Primary Hand Weapon (1H)"
		Requires.WEAPON_SECONDARY:
			return "Secondary Hand Weapon (1H)"
		_:
			return "Weapon"

func SetAttributes(item: InventoryItem) -> void:
	if item.attributes == null or item.attributes.size() == 0:
		attribute_one.text = ""
		attribute_two.text = ""
		attribute_three.text = ""
		return

	attribute_one.text = "+%s %s" % [item.attributes[0].attributeValue, item.attributes[0].GetAttributeName(item.attributes[0].attribute)]

	if item.attributes.size() < 2:
		attribute_two.text = ""
		attribute_three.text = ""
		return

	attribute_two.text = "+%s %s" % [item.attributes[1].attributeValue, item.attributes[1].GetAttributeName(item.attributes[1].attribute)]

	if item.attributes.size() < 3:
		attribute_three.text = ""
		return

	attribute_three.text = "+%s %s" % [item.attributes[2].attributeValue, item.attributes[2].GetAttributeName(item.attributes[2].attribute)]

func GetColorForQuality(quality: int) -> Color:
	match quality:
		ItemQuality.COMMON:
			return commonQualityColor
		ItemQuality.RARE:
			return rareQualityColor
		ItemQuality.SUPERIOR:
			return superiorQualityColor
		ItemQuality.ELITE:
			return eliteQualityColor
		_:
			return Color(211, 211, 211, 255)

func GetNameForSlot(slot: int) -> String:
	match slot:
		Requires.NONE:
			return ""
		Requires.ARM:
			return "Arm"
		Requires.CHEST:
			return "Chest"
		Requires.EAR:
			return "Ear"
		Requires.FEET:
			return "Feet"
		Requires.HANDS:
			return "Hands"
		Requires.HEAD:
			return "Head"
		Requires.LEGS:
			return "Legs"
		Requires.NECK:
			return "Neck"
		Requires.RING:
			return "Ring"
		Requires.WEAPON_1H:
			return "Either hand."
		Requires.WEAPON_2H:
			return "Both hands."
		Requires.WEAPON_PRIMARY:
			return "Primary hand"
		Requires.WEAPON_SECONDARY:
			return "Secondary hand"
		Requires.WRIST:
			return "Wrist"
		_:
			return ""
