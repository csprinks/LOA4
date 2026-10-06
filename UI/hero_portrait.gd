class_name HeroPortrait
extends TextureRect

## The portrait on a CharacterCard, doubling as a drop target for consumables:
## drag a potion from the backpack onto a hero's face to use it on that hero.
## Works in and out of combat -- the owning CharacterCard decides how to apply it
## (directly out of combat, through the active hero's turn for 2 AP in combat).
##
## Accepts a drag only when it carries a PotionData-backed item, and marks the
## source slot's drag "successful" only when the card actually commits to using
## the potion, so a rejected drop (wrong turn, not enough AP, already full) leaves
## the potion untouched in the backpack.

const HOVER_TINT := Color(1.25, 1.15, 0.6)   # warm glow while a valid potion hovers

var _base_modulate: Color = Color.WHITE

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var can := _potion_data(data) != null
	self_modulate = HOVER_TINT if can else _base_modulate
	return can

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	self_modulate = _base_modulate

	var variant := data as DragInventoryVariant
	if variant == null:
		return

	var card := owner as CharacterCard
	if card == null:
		return

	# The card returns true when it commits to consuming the potion (now, or as
	# the active hero's action this combat turn). Only then do we suppress the
	# source slot's restore-on-cancel so the used potion leaves the backpack.
	if card.try_receive_potion(variant.item, variant.myContainer) and variant.myContainer != null:
		variant.myContainer._dragDropSuccessful = true

func _notification(what: int) -> void:
	# The hover tint is applied during another control's drag; make sure it clears
	# even if the drag ends without ever dropping on us.
	if what == NOTIFICATION_DRAG_END:
		self_modulate = _base_modulate

# The PotionData resource behind a dragged item, or null if the drag isn't a
# usable potion.
func _potion_data(data: Variant) -> PotionData:
	var variant := data as DragInventoryVariant
	if variant == null or variant.item == null or variant.item._resourceData == null:
		return null
	return variant.item._resourceData as PotionData
