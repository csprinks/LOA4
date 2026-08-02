class_name InventoryItem
extends RefCounted

# there is an itemName in both InventoryData and InventoryItem because of procedural
# generation and Resources are combined. Resources all point to the same object -
# but when we procedurally generate based off of a resource we need the root name
# from the resource and then combine it with the prefix/suffix to get the final name
var itemName: String = "Item Name"
var _resourceData: InventoryData
var attributes: Array[Attributes] = []
var magicProperty: MagicProperty
var itemPrefix: String
var itemSuffix: String

var charges: int = 0

# How many units this single slot holds. This lives on the wrapper rather than on
# _resourceData because the resource is a shared .tres instance - writing to it
# would change every item created from that resource. Only stackable items ever
# carry a quantity above 1; everything else occupies one slot per unit.
var quantity: int = 1

func SetData(resourceData: InventoryData) -> void:
	_resourceData = resourceData

func UseItem() -> void:
	pass
