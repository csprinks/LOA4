class_name SwapItemUtility
extends RefCounted

static func CanSwap(dragVariant: DragInventoryVariant, slotRequirement: int) -> bool:
	var matchesSlotRequirement = dragVariant.item._resourceData.thisSlotRequires == slotRequirement
	var noRequirement = slotRequirement == Requires.NONE
	var otherSlotAcceptsThisItem = dragVariant.myContainer.slotRequirement == slotRequirement or dragVariant.myContainer.slotRequirement == Requires.NONE
	var canSwap = (matchesSlotRequirement or noRequirement) and otherSlotAcceptsThisItem

	return canSwap

static func CanSwapWeapon(draggedVariant: DragInventoryVariant, otherWeapon: InventoryContainer, slotRequirement: int) -> bool:
	var dragged_SlotRequirement = draggedVariant.item._resourceData.thisSlotRequires

	if dragged_SlotRequirement == Requires.WEAPON_2H:
		if otherWeapon == null:
			return true
		if not otherWeapon._item._resourceData.isBlank or otherWeapon._item._resourceData.thisSlotRequires == Requires.WEAPON_2H:
			return false
		return true

	# if a primary or secondary item is going in an appropriate slot, allow it
	if (dragged_SlotRequirement == Requires.WEAPON_PRIMARY and slotRequirement == Requires.WEAPON_PRIMARY) or (dragged_SlotRequirement == Requires.WEAPON_SECONDARY and slotRequirement == Requires.WEAPON_SECONDARY):
		return true

	# if a primary or secondary required is going in the wrong slot, return false
	if dragged_SlotRequirement == Requires.WEAPON_PRIMARY and slotRequirement != Requires.WEAPON_PRIMARY:
		return false

	if dragged_SlotRequirement == Requires.WEAPON_SECONDARY and slotRequirement != Requires.WEAPON_SECONDARY:
		return false

	# if we are dragging from a non-weapon slot we do not need to perform these checks
	if draggedVariant.myContainer.slotRequirement != Requires.NONE:
		if slotRequirement == Requires.WEAPON_PRIMARY or slotRequirement == Requires.WEAPON_SECONDARY:
			return not EitherSlotRequiresAndContainsAPrimaryOrSecondary(otherWeapon)
		# if we are trying to drag a normal 1H into a slot that already has a PRIMARY or SECONDARY then do not allow it
		if otherWeapon._item._resourceData.thisSlotRequires == Requires.WEAPON_PRIMARY or dragged_SlotRequirement == Requires.WEAPON_PRIMARY:
			# do not allow when a WEAPON_PRIMARY is already in the slot
			return false
		if otherWeapon._item._resourceData.thisSlotRequires == Requires.WEAPON_SECONDARY or dragged_SlotRequirement == Requires.WEAPON_SECONDARY:
			# do not allow when a WEAPON_SECONDARY is already in the slot
			return false

		if OtherSlotRequiresAndContainsAPrimaryOrSecondary(otherWeapon):
			return false

	# dragging a general 1H into a weapon slot
	if (dragged_SlotRequirement == Requires.WEAPON_1H and slotRequirement == Requires.WEAPON_PRIMARY) or (dragged_SlotRequirement == Requires.WEAPON_1H and slotRequirement == Requires.WEAPON_SECONDARY):
		if OtherSlotRequiresAndContainsAPrimaryOrSecondary(otherWeapon):
			return false
		return true

	return dragged_SlotRequirement == slotRequirement

static func EitherSlotRequiresAndContainsAPrimaryOrSecondary(otherWeapon: InventoryContainer) -> bool:
	# this is very hacky - but not sure a better way to do this
	# essentially each PRI/SEC weapon slot has a reference to the other, so we are relying on that to go back n forth
	if (otherWeapon._otherWeaponSlot.slotRequirement == Requires.WEAPON_PRIMARY and otherWeapon._otherWeaponSlot._item._resourceData.thisSlotRequires == Requires.WEAPON_PRIMARY) or (otherWeapon._otherWeaponSlot.slotRequirement == Requires.WEAPON_SECONDARY and otherWeapon._otherWeaponSlot._item._resourceData.thisSlotRequires == Requires.WEAPON_SECONDARY) or (otherWeapon._item._resourceData.thisSlotRequires == Requires.WEAPON_PRIMARY and otherWeapon.slotRequirement == Requires.WEAPON_PRIMARY) or (otherWeapon._item._resourceData.thisSlotRequires == Requires.WEAPON_SECONDARY and otherWeapon.slotRequirement == Requires.WEAPON_SECONDARY):
		return true

	return false

static func OtherSlotRequiresAndContainsAPrimaryOrSecondary(otherWeapon: InventoryContainer) -> bool:
	# this is very hacky - but not sure a better way to do this
	# essentially each PRI/SEC weapon slot has a reference to the other, so we are relying on that to go back n forth
	if (otherWeapon._otherWeaponSlot.slotRequirement == Requires.WEAPON_PRIMARY and otherWeapon._item._resourceData.thisSlotRequires == Requires.WEAPON_PRIMARY) or (otherWeapon._otherWeaponSlot.slotRequirement == Requires.WEAPON_SECONDARY and otherWeapon._item._resourceData.thisSlotRequires == Requires.WEAPON_SECONDARY):
		return true

	return false

static func SlotHasWeaponRequirement(slotRequirement: int) -> bool:
	var isWeaponRequirement = slotRequirement == Requires.WEAPON_1H or slotRequirement == Requires.WEAPON_2H or slotRequirement == Requires.WEAPON_PRIMARY or slotRequirement == Requires.WEAPON_SECONDARY

	return isWeaponRequirement
