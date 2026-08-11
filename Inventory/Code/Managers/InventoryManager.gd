extends Node
# NOTE: no class_name here — "InventoryManager" is already the name of the
# autoload singleton (Globals/inventory_manager.tscn); Godot forbids a global
# class_name that matches an existing autoload name.

@export var inventoryPrefab: PackedScene
@export var equipmentPrefab: PackedScene
@export var inspectorPanel: PackedScene
@export var inventoryResource: InventoryResource

var mainHandContainer: InventoryContainer
var offHandContainer: InventoryContainer

var inventoryInstance: InventoryExample
var equipmentInstance: Control
var inspectorHelper: InspectorHelper
@export var attributes: Attributes
var _inventoryEvents: Node
var _randomNumberManager: Node

@export var blankSprite: Texture2D

var inventory: Dictionary = {}
var equipment: Dictionary = {}

@export var maximumNumberOfAttributesOnItems: int = 3

func _ready() -> void:
	inventoryInstance = inventoryPrefab.instantiate() as InventoryExample
	inspectorHelper = inspectorPanel.instantiate() as InspectorHelper

	_randomNumberManager = get_node("/root/RandomNumberManager")
	_inventoryEvents = get_node("/root/InventoryEvents")
	_inventoryEvents.ShowInventory.connect(OnShowInventory)
	_inventoryEvents.ShowInspector.connect(OnShowInspector)
	_inventoryEvents.CloseInspector.connect(OnCloseInspector)

	add_child(inventoryInstance)
	add_child(inspectorHelper)

	call_deferred("HideUIOnStartup")
	# The backpack starts empty and is populated by the game flow: a new game
	# leaves it empty (items come from chests/loot), and loading a save restores
	# it via load_inventory(). (Previously this seeded 35 random items on every
	# boot, which both clobbered loaded saves and could never persist.)

func SeedRandomInventory() -> void:
	inventoryInstance.LoadItems(GetRandomItems(35))

#region Persistence
# Snapshot the shared backpack for the save file (array of item dicts, blanks as {}).
func serialize_inventory() -> Array:
	return inventoryInstance.serialize() if inventoryInstance else []

# Restore the shared backpack from a serialize_inventory() array.
func load_inventory(data: Array) -> void:
	if inventoryInstance:
		inventoryInstance.deserialize(data, _inventoryEvents)

# Empty the backpack (used when starting a new game).
func reset_inventory() -> void:
	if inventoryInstance:
		inventoryInstance.Clear()
#endregion

func HideUIOnStartup() -> void:
	if inspectorHelper:
		inspectorHelper.ShowInspector()
	OnShowInventory()

func OnShowInspector(inspectorData: InspectorDataVariant) -> void:
	inspectorHelper.ShowInspector()
	inspectorHelper.SetData(inspectorData)

func OnCloseInspector() -> void:
	inspectorHelper.CloseInspector()

func OnShowInventory() -> void:
	inventoryInstance.ShowInventory()

var MaximumNumberOfAttributesOnItems: int:
	get:
		var actualMaxAttributes = Attributes.AttributeTypes.values().size()
		var max = actualMaxAttributes if maximumNumberOfAttributesOnItems > actualMaxAttributes else maximumNumberOfAttributesOnItems
		return max
	set(value):
		maximumNumberOfAttributesOnItems = value

func GetWeapons() -> Array[InventoryItem]:
	var weaponData: Array[InventoryData] = []
	for i in inventoryResource.inventoryData:
		if i.itemType == ItemTypes.WEAPON:
			weaponData.append(i)

	var weaponItems: Array[InventoryItem] = []

	for item in weaponData:
		var weapon := InventoryWeapon.new()
		weapon._resourceData = item
		weapon.itemName = item.itemName
		weapon.attributes = attributes.GetNewRandomAttributes(Attributes.GetNumAttributesForQualityLevel(item.quality), item.quality)
		weapon.SetInventoryEvents(_inventoryEvents)
		weaponItems.append(weapon)

	return weaponItems

func GetRandomItems(numberOfItems: int) -> Array[InventoryItem]:
	var count = inventoryResource.inventoryData.size()

	var randomData: Array[InventoryData] = []

	for i in range(numberOfItems):
		var randomIndex = randi() % count
		var data = inventoryResource.inventoryData[randomIndex]
		randomData.append(data)

	var randomItems: Array[InventoryItem] = []

	for item in randomData:
		randomItems.append(CreateItemFromData(item))

	return randomItems

# Wrap a raw InventoryData resource into the correct runtime InventoryItem
# subtype (weapon / potion / generic), attaching random attributes and the
# inventory event bus as appropriate. Shared by random seeding and AddItem.
# Pass a quantity to override how many units the resulting slot holds; the
# default (-1) derives it from the resource - the full quantity for stackable
# items, a single unit for everything else.
func CreateItemFromData(data: InventoryData, quantity: int = -1) -> InventoryItem:
	if data == null:
		return null

	var item := _BuildItemForType(data)
	item.quantity = quantity if quantity >= 0 else GetStackSize(data)
	return item

# Stackable resources put their whole quantity in one slot; anything else is
# limited to a single unit per slot.
func GetStackSize(data: InventoryData) -> int:
	if data == null:
		return 0
	return maxi(1, data.quantity) if data.stackable else 1

func _BuildItemForType(data: InventoryData) -> InventoryItem:
	if data.itemType == ItemTypes.WEAPON:
		var weapon := InventoryWeapon.new()
		weapon._resourceData = data
		weapon.itemName = data.itemName
		weapon.attributes = _RollAttributes(data)
		weapon.SetInventoryEvents(_inventoryEvents)
		return weapon
	elif data.itemType == ItemTypes.POTION:
		var potionType := PotionTypes.HEALTH
		if data is PotionData:
			potionType = data.potionType
		var potion := Potion.new(potionType)
		potion._resourceData = data
		potion.itemName = data.itemName
		potion.attributes = []
		potion.SetInventoryEvents(_inventoryEvents)
		return potion
	else:
		var inventoryItem := InventoryItem.new()
		inventoryItem._resourceData = data
		inventoryItem.itemName = data.itemName
		inventoryItem.attributes = _RollAttributes(data)
		return inventoryItem

# Roll procedural bonus attributes for an item, honoring the resource's
# randomizeAttributes flag. Returns an empty array when randomization is off, so
# hand-authored / fixed-stat items stay clean.
func _RollAttributes(data: InventoryData) -> Array[Attributes]:
	if not data.randomizeAttributes:
		return []
	return attributes.GetNewRandomAttributes(Attributes.GetNumAttributesForQualityLevel(data.quality), data.quality)

# Add an item (from an InventoryData resource) to the player's inventory at
# runtime. A stackable resource lands in a single slot carrying its full
# quantity; a non-stackable one takes a separate slot per unit, so moving a slot
# later can never destroy the extras. Returns the number of units actually
# added, which is 0 when the inventory is full and less than the requested
# amount when it fills up partway through.
func AddItem(data: InventoryData) -> int:
	if data == null:
		return 0

	if data.stackable:
		var stackSize := GetStackSize(data)
		return stackSize if inventoryInstance.AddItem(CreateItemFromData(data, stackSize)) else 0

	var wanted := maxi(1, data.quantity)
	var added := 0
	for i in wanted:
		if not inventoryInstance.AddItem(CreateItemFromData(data, 1)):
			break
		added += 1

	return added

func CreateEquipmentForSlotType(slotRequirement: int) -> InventoryData:
	var matchingItems: Array[InventoryData] = []
	for item in inventoryResource.inventoryData:
		if item.thisSlotRequires == slotRequirement:
			matchingItems.append(item)

	# If no matching items found, return null
	if matchingItems.size() == 0:
		return null

	var randomIndex = randi() % matchingItems.size()
	return matchingItems[randomIndex]
