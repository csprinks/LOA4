class_name SlotCard
extends RefCounted

## Builds one save-slot card for the Load Game / New Game slot screens: a clickable
## Button with the slot number, party names, and crowns laid over it. The caller
## connects `pressed` — this helper only builds the visuals.
##
## Shared by load_game.gd and new_game.gd so the two screens stay identical in look.

const CROWN_ICON := preload("res://Crowns/Crowns_Icon.png")


# summary: { exists: bool, names: Array, crowns: int } from SaveSystem.get_slot_summary.
# enabled: whether the card is selectable. Load Game enables only populated slots;
#          New Game enables every slot. Disabled cards are dimmed and take no clicks.
# show_delete: adds a "Delete" button (named "DeleteButton") to populated cards; it
#          intercepts its own clicks so it doesn't trigger the card. The caller finds
#          it via card.find_child("DeleteButton") and connects its `pressed`.
static func build(slot: int, summary: Dictionary, enabled: bool, show_delete: bool = false) -> Button:
	var exists: bool = summary.get("exists", false)

	var card := Button.new()
	card.custom_minimum_size = Vector2(760, 104)
	card.disabled = not enabled
	if not enabled:
		card.modulate = Color(1, 1, 1, 0.5)  # dim (labels included)

	# Child controls ignore the mouse so clicks fall through to the button.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)

	# Left: the slot number.
	var slot_label := Label.new()
	slot_label.text = "Slot %d" % (slot + 1)
	slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_label.custom_minimum_size = Vector2(140, 0)
	slot_label.add_theme_font_size_override("font_size", 30)
	slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(slot_label)

	# Middle: the party names (or "Empty"); expands to push crowns to the right.
	var party_label := Label.new()
	party_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	party_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	party_label.add_theme_font_size_override("font_size", 22)
	party_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if exists:
		var names: Array = summary.get("names", [])
		party_label.text = " · ".join(names) if not names.is_empty() else "Saved party"
	else:
		party_label.text = "Empty"
		party_label.add_theme_color_override("font_color", Color(0.8745098, 0.8745098, 0.7882353, 0.8))
	row.add_child(party_label)

	# Right: crowns (icon + amount), only for populated slots.
	if exists:
		var crowns_box := HBoxContainer.new()
		crowns_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crowns_box.alignment = BoxContainer.ALIGNMENT_END
		crowns_box.add_theme_constant_override("separation", 6)

		var icon := TextureRect.new()
		icon.texture = CROWN_ICON
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crowns_box.add_child(icon)

		var crowns_label := Label.new()
		crowns_label.text = str(summary.get("crowns", 0))
		crowns_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		crowns_label.add_theme_font_size_override("font_size", 24)
		crowns_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crowns_box.add_child(crowns_label)

		row.add_child(crowns_box)

	# Optional per-slot delete button (populated slots only). It keeps its default
	# mouse_filter (STOP) so a click on it doesn't fall through to the card button.
	if show_delete and exists:
		var delete_btn := Button.new()
		delete_btn.name = "DeleteButton"
		delete_btn.text = "Delete"
		delete_btn.custom_minimum_size = Vector2(120, 60)
		delete_btn.add_theme_font_size_override("font_size", 20)
		row.add_child(delete_btn)

	return card
