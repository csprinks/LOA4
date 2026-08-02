class_name EquipmentSerializer
extends RefCounted

# Converts an equipped InventoryItem to/from a plain, JSON-serializable Dictionary
# so equipped gear can be persisted in a character's save data. Equipped items
# reference a shared InventoryData resource (.tres) for their icon/name/stats, so
# we store that resource path plus the per-item data that lives on the wrapper
# (name, prefix/suffix, charges, procedurally generated attributes).

# Returns {} for an empty/blank slot.
static func item_to_dict(item: InventoryItem) -> Dictionary:
	if item == null or item._resourceData == null or item._resourceData.isBlank:
		return {}

	var res_path := item._resourceData.resource_path
	if res_path == "":
		# Can't reconstruct an item that isn't backed by a saved resource.
		return {}

	var attrs: Array = []
	for a in item.attributes:
		if a != null:
			attrs.append({"attribute": a.attribute, "value": a.attributeValue})

	return {
		"resource_path": res_path,
		"itemName": item.itemName,
		"itemPrefix": item.itemPrefix,
		"itemSuffix": item.itemSuffix,
		"charges": item.charges,
		"quantity": item.quantity,
		"is_weapon": item is InventoryWeapon,
		"attributes": attrs,
	}

# Rebuilds an InventoryItem from a dict produced by item_to_dict. Returns null
# for an empty dict or if the backing resource no longer exists.
static func item_from_dict(data: Dictionary, inventory_events: Node) -> InventoryItem:
	if data == null or data.is_empty():
		return null

	var res_path: String = data.get("resource_path", "")
	if res_path == "" or not ResourceLoader.exists(res_path):
		return null

	var res := load(res_path) as InventoryData
	if res == null:
		return null

	var item: InventoryItem
	if data.get("is_weapon", false):
		var weapon := InventoryWeapon.new()
		if inventory_events:
			weapon.SetInventoryEvents(inventory_events)
		item = weapon
	else:
		item = InventoryItem.new()

	item._resourceData = res
	item.itemName = data.get("itemName", res.itemName)
	item.itemPrefix = data.get("itemPrefix", "")
	item.itemSuffix = data.get("itemSuffix", "")
	item.charges = int(data.get("charges", 0))
	item.quantity = maxi(1, int(data.get("quantity", 1)))

	var attrs: Array[Attributes] = []
	for ad in data.get("attributes", []):
		var a := Attributes.new()
		a.attribute = int(ad.get("attribute", 0))
		a.attributeValue = int(ad.get("value", 0))
		attrs.append(a)
	item.attributes = attrs

	return item
