class_name InventoryContainer
extends TextureRect

# Emitted whenever the item held in this slot changes (equip, unequip, swap).
# The character card connects its two weapon slots to persist equipped gear.
signal slot_changed

@export var equippedItemTextureRect: TextureRect

@export_group("Drag and Drop Tinting")
@export var _default_Color: Color = Color(1, 0, 0, 1)
@export var _can_NOT_drag_Color: Color = Color(1, 0, 0, 1)
@export var _CAN_drag_Color: Color = Color(1, 0, 0, 1)

@export_group("Container Requirements")
@export_enum("NONE", "ARM", "CHEST", "EAR", "FEET", "HANDS", "HEAD", "LEGS", "NECK", "RING", "WRIST", "WEAPON_1H", "WEAPON_2H", "WEAPON_PRIMARY", "WEAPON_SECONDARY")
var slotRequirement: int = Requires.NONE

@export_group("Default Background Icons")
@export var helmetIcon: Texture2D
@export var chestIcon: Texture2D
@export var pantsIcon: Texture2D
@export var handIcon: Texture2D
@export var blankIcon: Texture2D

@export_group("Reference to other Weapon Slot Nodes if Applicable")
@export var _otherWeaponSlot: InventoryContainer

var _inventoryEvents: Node
var _originalTextureBeforeDrag: Texture2D = null
var _item: InventoryItem = null
var stackText: Label
var _dragDropSuccessful: bool = false
var _mouseExited: bool = false
var _mouseHoverTimer: Timer = null
var _itemReuseTimer: Timer = null
var canUseItem: bool = true

func _ready() -> void:
	print("Inventory Container Ready")

	_inventoryEvents = get_node("/root/InventoryEvents")

	_mouseHoverTimer = get_node("Timer")
	_mouseHoverTimer.timeout.connect(OnWaitForMouseHoverTimeout)

	_itemReuseTimer = get_node("ItemReuseTimer")
	_itemReuseTimer.timeout.connect(func(): canUseItem = true)

	stackText = get_node("stacktext")
	stackText.text = ""

	ClearData()
	SetSlotIcon()

	mouse_entered.connect(OnMouseEntered)
	mouse_exited.connect(OnMouseExited)

func IsBlank() -> bool:
	return _item._resourceData.isBlank

func SetSlotIcon() -> void:
	match slotRequirement:
		Requires.CHEST:
			texture = chestIcon
		Requires.HEAD:
			texture = helmetIcon
		Requires.FEET:
			texture = pantsIcon
		Requires.WEAPON_1H, Requires.WEAPON_2H, Requires.WEAPON_PRIMARY, Requires.WEAPON_SECONDARY:
			texture = handIcon
		_:
			pass

func SetData(item: InventoryItem) -> void:
	_item = item
	equippedItemTextureRect.texture = item._resourceData.icon
	UpdateStackText()
	SetSlotIcon()
	slot_changed.emit()

# Stack count comes from the item wrapper, not the shared resource, so each slot
# shows its own amount. Must be called any time _item is reassigned.
func UpdateStackText() -> void:
	var count := _item.quantity if _item != null else 0
	stackText.text = str(count) if count > 1 else ""

func ClearData() -> InventoryItem:
	var resourceData := InventoryData.new()
	resourceData.icon = blankIcon
	resourceData.itemName = ""
	resourceData.description = ""
	resourceData.thisSlotRequires = Requires.NONE
	resourceData.price = 0
	resourceData.quantity = 0
	resourceData.isBlank = true

	_item = InventoryItem.new()
	_item.SetData(resourceData)
	_item.itemName = ""
	_item.quantity = 0

	return _item

func _get_drag_data(_at_position: Vector2) -> Variant:
	var previewTextureRect := TextureRect.new()
	previewTextureRect.texture = equippedItemTextureRect.texture
	# Constrain the preview to the slot's size and let the texture scale down to
	# fit; without this a large source icon (e.g. 256x256) draws at its native
	# resolution and spills across several slots while dragging.
	previewTextureRect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	previewTextureRect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	previewTextureRect.custom_minimum_size = size
	previewTextureRect.size = size

	set_drag_preview(previewTextureRect)

	var dragVariant := DragInventoryVariant.new()
	dragVariant.item = _item
	dragVariant.icon = equippedItemTextureRect.texture
	dragVariant.myContainer = self

	_originalTextureBeforeDrag = equippedItemTextureRect.texture
	_dragDropSuccessful = false
	equippedItemTextureRect.texture = blankIcon

	return dragVariant

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# If we have a stored original texture and the current texture is still blank,
		# it means the drag was cancelled, so restore the original texture
		if _originalTextureBeforeDrag != null and not _dragDropSuccessful:
			equippedItemTextureRect.texture = _originalTextureBeforeDrag

		# Clear the stored texture
		_originalTextureBeforeDrag = null
		_dragDropSuccessful = false

		# Reset color in case it was changed during drag
		SetColor(_default_Color)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var dragVariant: DragInventoryVariant = data

	if dragVariant.item == null:
		return false

	if _item._resourceData.isBlank:
		return CanDropOnBlankSlot(dragVariant)

	return CanDropOnNonBlankSlot(dragVariant)

func CanDropOnBlankSlot(dragVariant: DragInventoryVariant) -> bool:
	var canSwap = false
	if SwapItemUtility.SlotHasWeaponRequirement(slotRequirement):
		if _otherWeaponSlot._item._resourceData.thisSlotRequires == Requires.WEAPON_2H:
			canSwap = false
		elif not SwapItemUtility.SlotHasWeaponRequirement(dragVariant.item._resourceData.thisSlotRequires):
			# you are dragging a non-weapon into a weapon required slot
			canSwap = false
		else:
			canSwap = SwapItemUtility.CanSwapWeapon(dragVariant, _otherWeaponSlot, slotRequirement)
	else:
		canSwap = dragVariant.item._resourceData.thisSlotRequires == slotRequirement or slotRequirement == Requires.NONE

	if dragVariant.item != _item: # as long as the item is not the same as the one being dragged update the color
		UpdateDragStatusColor(canSwap, dragVariant)

	return canSwap

func CanDropOnNonBlankSlot(dragVariant: DragInventoryVariant) -> bool:
	var canSwap = false

	if SwapItemUtility.SlotHasWeaponRequirement(slotRequirement):
		if _otherWeaponSlot._item._resourceData.thisSlotRequires == Requires.WEAPON_2H:
			canSwap = false
		elif not SwapItemUtility.SlotHasWeaponRequirement(dragVariant.item._resourceData.thisSlotRequires):
			canSwap = false
		else:
			canSwap = SwapItemUtility.CanSwapWeapon(dragVariant, _otherWeaponSlot, slotRequirement)
	else:
		canSwap = SwapItemUtility.CanSwap(dragVariant, slotRequirement)

	if dragVariant.item != _item:
		UpdateDragStatusColor(canSwap, dragVariant)

	return canSwap

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var dragVariant: DragInventoryVariant = data

	if dragVariant.item == null:
		return

	# Mark the drag as successful in the source container
	if dragVariant.myContainer != null:
		dragVariant.myContainer._dragDropSuccessful = true

	# there is already an item here, so we need to swap it with the new item
	if not _item._resourceData.isBlank:
		if _item._resourceData.itemType == ItemTypes.WEAPON and SwapItemUtility.CanSwapWeapon(dragVariant, _otherWeaponSlot, slotRequirement):
			var swapItem = _item
			_item = dragVariant.item
			equippedItemTextureRect.texture = dragVariant.icon
			dragVariant.myContainer.SetData(swapItem)
			print("Setting Icon for Weapon ")
		elif SwapItemUtility.CanSwap(dragVariant, slotRequirement):
			var swapItem = _item
			_item = dragVariant.item
			equippedItemTextureRect.texture = dragVariant.icon
			dragVariant.myContainer.SetData(swapItem)
			print("Setting Icon for regular item ")
	else:
		# there was no item here, so we can set the new item and clear it from old slot
		print("Clearing icon for no item here")
		_item = dragVariant.item
		equippedItemTextureRect.texture = dragVariant.icon

		var clearedData = dragVariant.myContainer.ClearData()
		dragVariant.myContainer.SetData(clearedData)

	SetColor(_default_Color)
	dragVariant.myContainer.SetColor(_default_Color)

	# This slot's _item was assigned directly above (not via SetData) in the
	# swap/blank-target paths, so refresh the stack count and notify listeners.
	UpdateStackText()
	slot_changed.emit()

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_RIGHT:
		return

	if _item._resourceData.isBlank:
		return

	if _item._resourceData.itemType == ItemTypes.WEAPON:
		if slotRequirement != Requires.WEAPON_1H and slotRequirement != Requires.WEAPON_SECONDARY and slotRequirement != Requires.WEAPON_2H and slotRequirement != Requires.WEAPON_PRIMARY:
			return

	OnRightClick()

func OnRightClick() -> void:
	if _item == null or _item._resourceData.isBlank or not canUseItem:
		return

	canUseItem = false
	_itemReuseTimer.start()

	_item.UseItem()

func UpdateDragStatusColor(canSwap: bool, _dragVariant: DragInventoryVariant) -> void:
	var newColor = _CAN_drag_Color if canSwap else _can_NOT_drag_Color
	self_modulate = newColor
	SetColor(newColor)

func SetColor(newColor: Color) -> void:
	self_modulate = newColor

func OnMouseEntered() -> void:
	if _item._resourceData.isBlank:
		return

	_mouseExited = false
	_mouseHoverTimer.stop()
	_mouseHoverTimer.start()

func OnWaitForMouseHoverTimeout() -> void:
	print("waiting for mouse hover timeout")
	if _mouseExited:
		return

	var inspectorData := InspectorDataVariant.new()
	inspectorData.item = _item
	inspectorData.icon = equippedItemTextureRect.texture
	inspectorData.mousePosition = get_viewport().get_mouse_position()

	print("Emitting show inspector")
	_inventoryEvents.EmitShowInspector(inspectorData)

func OnMouseExited() -> void:
	_mouseExited = true
	SetColor(_default_Color)
	_inventoryEvents.EmitCloseInspector()

func GetData() -> InventoryItem:
	return _item
