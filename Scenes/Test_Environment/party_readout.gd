extends CanvasLayer

## Temporary Phase-2 party readout: shows the party held in PartyManager so you
## can confirm the heroes created on the Character Creation screen carried into
## the level. This is scaffolding — the real hero-card HUD (Phase 4) replaces it.
## Press Tab to toggle.

const STAT_ABBREV := {
	"Might": "MIG", "Awareness": "AWR", "Finesse": "FIN",
	"Intellect": "INT", "Charm": "CHM", "Fate": "FAT",
}

var _panel: PanelContainer


func _ready() -> void:
	layer = 50
	_build()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		if _panel:
			_panel.visible = not _panel.visible
			get_viewport().set_input_as_handled()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 16)
	_panel.modulate = Color(1, 1, 1, 0.95)
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var title := Label.new()
	title.text = "PARTY  (Tab to hide)"
	col.add_child(title)

	var party := _get_party()
	if party.is_empty():
		var empty := Label.new()
		empty.text = "No party — launch from the Character Creation screen."
		col.add_child(empty)
		return

	for i in range(party.size()):
		col.add_child(_hero_row(i + 1, party[i]))


func _get_party() -> Array:
	var pm := get_node_or_null("/root/PartyManager")
	if pm and "party" in pm:
		return pm.party
	return []


func _hero_row(number: int, hero) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	# Portrait
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(56, 56)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if hero.portrait != "" and ResourceLoader.exists(hero.portrait):
		portrait.texture = load(hero.portrait)
	row.add_child(portrait)

	# Text block
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var name_label := Label.new()
	name_label.text = "%d. %s" % [number, hero.character_name]
	info.add_child(name_label)

	var classes := _class_text(hero)
	if classes != "":
		var class_label := Label.new()
		class_label.text = classes
		info.add_child(class_label)

	var meta := Label.new()
	meta.text = "Lv %d   HP %d/%d" % [
		hero.level_system.current_level,
		hero.hit_points.current,
		hero.hit_points.max_value,
	]
	info.add_child(meta)

	var stats_label := Label.new()
	stats_label.text = _stats_text(hero)
	info.add_child(stats_label)

	return row


func _class_text(hero) -> String:
	var primary: String = hero.primary_class
	var secondary: String = hero.secondary_class
	if primary != "" and secondary != "":
		return "%s / %s" % [primary, secondary]
	if primary != "":
		return primary
	if secondary != "":
		return secondary
	return ""


func _stats_text(hero) -> String:
	var parts: PackedStringArray = []
	for stat_name in Character.STAT_NAMES:
		var stat = hero.get_stat(stat_name)
		if stat:
			parts.append("%s %d" % [STAT_ABBREV.get(stat_name, stat_name), stat.total])
	return "   ".join(parts)
