class_name CharacterSheet
extends HBoxContainer

## One hero's character sheet, built in code: identity, vitals, attributes and
## equipment on the left; the six attribute skill lines in the middle; the
## selected skill's details and the buy / upgrade controls on the right.
##
## Doubles as character creation (creation_mode: portrait, name and title are
## editable and every change is written straight to the Character) and as the
## in-game sheet (identity read-only; skill changes are a draft until commit()).
## Purchases run against a draft SkillBook either way, so Undo and Respec work
## the same in both. Skill changes animate (the SkillNodes pop, the numbers they
## moved punch); binding another hero snaps straight to their state.

signal changed

const PORTRAIT_DIR := "res://Portraits/"
const PORTRAIT_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "svg"]
const EQUIP_LABELS := {
	"primary": "Main", "secondary": "Off",
	"consumable1": "Quick 1", "consumable2": "Quick 2",
	"head": "Head", "chest": "Chest", "hands": "Hands",
	"feet": "Feet", "neck": "Neck", "ring": "Ring",
}

# Set before the sheet enters the tree.
var creation_mode := false

var _character: Character
var _draft := SkillBook.new()
var _undo: Array = []                # draft snapshots (SkillBook.to_dict), newest last
var _selected: SkillDefinition
var _animate := false                # the refresh in progress follows a skill change
var _shown_totals: Dictionary = {}   # attribute -> total last shown, to punch only what moved
var _shown_points := -1
var _punches: Dictionary = {}        # Control -> its running punch Tween
var _detail_fade: Tween

var _portrait: TextureRect
var _portrait_paths: Array[String] = []
var _name_edit: LineEdit
var _title_edit: LineEdit
var _name_label: Label
var _title_label: Label
var _level_label: Label
var _vitals_label: Label
var _stat_labels: Dictionary = {}    # attribute -> Label (left column total)
var _line_labels: Dictionary = {}    # attribute -> Label (skill line header total)
var _raise_buttons: Dictionary = {}  # attribute -> Button (buy a raw +1)
var _equip_labels: Dictionary = {}   # slot key -> Label
var _nodes: Dictionary = {}          # skill id -> SkillNode
var _points_label: Label
var _detail_text: VBoxContainer
var _detail_name: Label
var _detail_line: Label
var _detail_description: Label
var _detail_rank: Label
var _detail_status: Label
var _action_button: Button
var _undo_button: Button
var _respec_button: Button


func _ready() -> void:
	add_theme_constant_override("separation", 24)
	_build_identity_column()
	add_child(VSeparator.new())
	_build_tree_column()
	add_child(VSeparator.new())
	_build_detail_column()
	if _character:
		_refresh()


# Show `character`, starting a fresh draft from their confirmed skills.
func bind(character: Character) -> void:
	_character = character
	_draft = character.skills.duplicate_book()
	_undo.clear()
	_shown_totals.clear()
	_shown_points = -1
	if _selected == null:
		_selected = SkillTree.line(Character.STAT_NAMES[0])[0]
	if is_node_ready():
		_refresh()


# True while the draft holds skill changes not yet written to the Character.
func has_pending() -> bool:
	return _character != null and not _draft.equals(_character.skills)


func commit() -> void:
	if _character == null:
		return
	_character.apply_skills(_draft)
	if not creation_mode:
		_undo.clear()
	_refresh()


#region Build
func _label(text: String, size: int, color: Color = UIStyle.CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build_identity_column() -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(300, 0)
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(130, 130)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_portrait)

	if creation_mode:
		_portrait_paths = list_portraits()
		_portrait.mouse_filter = Control.MOUSE_FILTER_STOP
		_portrait.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_portrait.gui_input.connect(_on_portrait_input)
		var hint := _label("(click portrait to change)", 13, UIStyle.MUTED)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(hint)

		_name_edit = LineEdit.new()
		_name_edit.placeholder_text = "Enter Hero Name"
		_name_edit.max_length = 24
		_name_edit.add_theme_font_size_override("font_size", 20)
		_name_edit.text_changed.connect(_on_name_changed)
		col.add_child(_name_edit)

		_title_edit = LineEdit.new()
		_title_edit.placeholder_text = "Title (e.g. Paladin)"
		_title_edit.max_length = 24
		_title_edit.add_theme_font_size_override("font_size", 20)
		_title_edit.text_changed.connect(_on_title_changed)
		col.add_child(_title_edit)
	else:
		_name_label = _label("", 28, UIStyle.GOLD)
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(_name_label)
		_title_label = _label("", 18, UIStyle.MUTED)
		_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(_title_label)

	_level_label = _label("", 18, UIStyle.GOLD_BRIGHT)
	col.add_child(_level_label)
	_vitals_label = _label("", 18)
	col.add_child(_vitals_label)

	col.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 2)
	col.add_child(grid)
	for attribute in Character.STAT_NAMES:
		var name_label := _label(attribute, 20, SkillTree.color_of(attribute).lightened(0.25))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		var total := _label("", 20)
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stat_labels[attribute] = total
		grid.add_child(total)

	col.add_child(HSeparator.new())
	col.add_child(_label("Equipment", 16, UIStyle.MUTED))
	var equip_grid := GridContainer.new()
	equip_grid.columns = 2
	equip_grid.add_theme_constant_override("h_separation", 12)
	col.add_child(equip_grid)
	for slot in Character.EQUIPMENT_SLOTS:
		var line := _label("", 14)
		line.clip_text = true
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_equip_labels[slot] = line
		equip_grid.add_child(line)


func _build_tree_column() -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	add_child(col)

	_points_label = _label("", 22, UIStyle.GOLD_BRIGHT)
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_points_label)

	for attribute in Character.STAT_NAMES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(row)

		var header := _label("", 20, SkillTree.color_of(attribute).lightened(0.25))
		header.custom_minimum_size = Vector2(140, 0)
		header.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_line_labels[attribute] = header
		row.add_child(header)

		# A raw +1 to the attribute, with no skill attached.
		var raise := Button.new()
		raise.text = "+"
		raise.custom_minimum_size = Vector2(34, 34)
		raise.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		raise.add_theme_font_size_override("font_size", 20)
		raise.tooltip_text = "+1 %s  (%d ATR)" % [attribute, SkillTree.ATTRIBUTE_POINT_COST]
		raise.pressed.connect(_on_raise_pressed.bind(attribute))
		_raise_buttons[attribute] = raise
		row.add_child(raise)

		var gap := Control.new()
		gap.custom_minimum_size = Vector2(14, 0)
		row.add_child(gap)

		for skill in SkillTree.line(attribute):
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 0)
			cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(cell)

			var node := SkillNode.new(skill)
			node.pressed.connect(_select.bind(skill))
			node.focus_entered.connect(_select.bind(skill))
			node.activated.connect(_on_node_activated.bind(skill))
			_nodes[skill.id] = node
			cell.add_child(node)

			var caption := _label(skill.display_name, 14, UIStyle.MUTED)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			caption.custom_minimum_size = Vector2(SkillNode.NODE_SIZE.x, 0)
			caption.clip_text = true
			cell.add_child(caption)


func _build_detail_column() -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(340, 0)
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	# The selected skill's text sits in its own box so it can fade in as one.
	_detail_text = VBoxContainer.new()
	_detail_text.add_theme_constant_override("separation", 10)
	col.add_child(_detail_text)

	_detail_name = _label("", 30, UIStyle.GOLD)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.add_child(_detail_name)
	_detail_line = _label("", 16, UIStyle.MUTED)
	_detail_text.add_child(_detail_line)
	_detail_description = _label("", 18)
	_detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_description.custom_minimum_size = Vector2(0, 110)
	_detail_text.add_child(_detail_description)
	_detail_rank = _label("", 18)
	_detail_rank.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.add_child(_detail_rank)
	_detail_status = _label("", 16, UIStyle.MUTED)
	_detail_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.add_child(_detail_status)

	_action_button = Button.new()
	_action_button.custom_minimum_size = Vector2(0, 48)
	_action_button.add_theme_font_size_override("font_size", 22)
	_action_button.pressed.connect(_advance_selected)
	col.add_child(_action_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	_undo_button = Button.new()
	_undo_button.text = "Undo"
	_undo_button.add_theme_font_size_override("font_size", 20)
	_undo_button.pressed.connect(_on_undo_pressed)
	col.add_child(_undo_button)

	_respec_button = Button.new()
	_respec_button.text = "Respec (refund all)"
	_respec_button.add_theme_font_size_override("font_size", 20)
	_respec_button.pressed.connect(_on_respec_pressed)
	col.add_child(_respec_button)
#endregion


#region Skill actions
func _available_points() -> int:
	return _character.attribute_points_earned - _draft.points_spent


func _select(skill: SkillDefinition) -> void:
	if _selected == skill:
		return
	_selected = skill
	_refresh_tree()
	_refresh_detail()
	if _detail_fade:
		_detail_fade.kill()
	_detail_text.modulate.a = 0.0
	_detail_fade = create_tween()
	_detail_fade.tween_property(_detail_text, "modulate:a", 1.0, 0.18)


func _on_node_activated(skill: SkillDefinition) -> void:
	_selected = skill
	_advance_selected()


func _advance_selected() -> void:
	if _character == null or _selected == null:
		return
	var snapshot := _draft.to_dict()
	if _draft.advance(_selected, _available_points()):
		_undo.append(snapshot)
		_draft_changed()
		_punch(_action_button, 1.08)
	else:
		_refresh()
		_nodes[_selected.id].play_denied()


func _on_raise_pressed(attribute: String) -> void:
	if _character == null:
		return
	var snapshot := _draft.to_dict()
	if _draft.buy_attribute(attribute, _available_points()):
		_undo.append(snapshot)
		_draft_changed()
		_punch(_raise_buttons[attribute], 1.25)


func _on_undo_pressed() -> void:
	if _undo.is_empty():
		return
	_draft.from_dict(_undo.pop_back())
	_draft_changed()


func _on_respec_pressed() -> void:
	if _draft.is_blank():
		return
	_undo.append(_draft.to_dict())
	_draft.reset()
	_draft_changed()


func _draft_changed() -> void:
	_animate = true
	if creation_mode:
		commit()
	else:
		_refresh()
	_animate = false
	changed.emit()


# A quick swell-and-settle on a control whose value just changed.
func _punch(control: Control, peak: float = 1.3) -> void:
	if _punches.has(control):
		_punches[control].kill()
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(peak, peak)
	var tween := create_tween()
	tween.tween_property(control, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_punches[control] = tween
#endregion


#region Refresh
func _refresh() -> void:
	if _character == null:
		return
	_refresh_identity()
	_refresh_tree()
	_refresh_detail()


func _refresh_identity() -> void:
	if _character.portrait != "" and ResourceLoader.exists(_character.portrait):
		_portrait.texture = load(_character.portrait)

	if creation_mode:
		# Only touch the text when it differs, so typing doesn't reset the caret.
		if _name_edit.text != _character.character_name:
			_name_edit.text = _character.character_name
		if _title_edit.text != _character.title:
			_title_edit.text = _character.title
	else:
		_name_label.text = _character.character_name
		_title_label.text = _character.title
		_title_label.visible = _character.title != ""

	var levels := _character.level_system
	if levels.current_level >= levels.max_level:
		_level_label.text = "Level %d  (max)" % levels.current_level
	else:
		_level_label.text = "Level %d    XP %d / %d" % [levels.current_level, levels.current_xp,
			LevelSystem.XP_CHART[levels.current_level + 1]["cumulative"]]

	_vitals_label.text = "HP %d / %d      AP %d / %d\nFortune %d      Armor %d" % [
		_character.hit_points.current, _character.hit_points.max_value,
		_character.action_points.current, _character.action_points.max_value,
		_character.fortune_points.current, _character.armor.value]

	for slot in Character.EQUIPMENT_SLOTS:
		var item: Dictionary = _character.get_equipment_slot(slot)
		var item_name := " ".join(PackedStringArray([item.get("itemPrefix", ""),
			item.get("itemName", ""), item.get("itemSuffix", "")])).strip_edges()
		_equip_labels[slot].text = "%s: %s" % [EQUIP_LABELS.get(slot, slot), item_name if item_name != "" else "-"]
		_equip_labels[slot].tooltip_text = item_name
		_equip_labels[slot].add_theme_color_override("font_color",
			UIStyle.CREAM if item_name != "" else UIStyle.MUTED)


func _refresh_tree() -> void:
	var points := _available_points()
	if _draft.free_picks_left > 0:
		_points_label.text = "Free skills to choose: %d        Attribute Points: %d" % [_draft.free_picks_left, points]
	else:
		_points_label.text = "Attribute Points: %d" % points
	if _animate and points != _shown_points:
		_punch(_points_label, 1.15)
	_shown_points = points

	for attribute in Character.STAT_NAMES:
		var stat := _character.get_stat(attribute)
		var total := stat.base + _draft.stat_bonus(attribute)
		var raised := total != stat.total
		_line_labels[attribute].text = "%s  %d" % [attribute, total]
		_stat_labels[attribute].text = str(total)
		_stat_labels[attribute].add_theme_color_override("font_color",
			UIStyle.GOLD_BRIGHT if raised else UIStyle.CREAM)
		if _animate and total != int(_shown_totals.get(attribute, total)):
			_punch(_stat_labels[attribute], 1.5)
			_punch(_line_labels[attribute], 1.2)
		_shown_totals[attribute] = total
		_raise_buttons[attribute].disabled = not _draft.can_buy_attribute(points)

		var line := SkillTree.line(attribute)
		for i in line.size():
			var skill: SkillDefinition = line[i]
			var rank := _draft.rank_of(skill)
			var state := SkillNode.State.LOCKED
			if rank > 0:
				state = SkillNode.State.OWNED
			elif _draft.is_reachable(skill):
				state = SkillNode.State.AVAILABLE
			var next_owned: bool = i + 1 < line.size() and _draft.rank_of(line[i + 1]) > 0
			_nodes[skill.id].show_state(state, rank, skill == _selected,
				rank != _character.skills.rank_of(skill), next_owned,
					_draft.can_advance(skill, points), _animate)

	_undo_button.disabled = _undo.is_empty()
	_respec_button.disabled = _draft.is_blank()


func _refresh_detail() -> void:
	var skill := _selected
	if skill == null or _character == null:
		return
	var rank := _draft.rank_of(skill)
	var cost := _draft.next_cost(skill)

	_detail_name.text = skill.display_name
	_detail_line.text = "%s  -  Tier %s" % [skill.attribute, SkillNode.ROMAN[skill.position - 1]]
	_detail_description.text = skill.description
	_detail_rank.text = "Rank %d / %d\n+%d %s per rank" % [rank, SkillTree.MAX_RANK, skill.position, skill.attribute]

	_detail_status.text = ""
	_action_button.disabled = false
	if rank >= SkillTree.MAX_RANK:
		_action_button.text = "Mastered"
		_action_button.disabled = true
	elif cost < 0:
		_action_button.text = "Locked"
		_action_button.disabled = true
		_detail_status.text = "Requires %s." % SkillTree.prerequisite(skill).display_name
	else:
		var verb := "Upgrade to Rank %d" % (rank + 1) if rank > 0 else "Learn"
		_action_button.text = "%s  (%s)" % [verb, "Free" if cost == 0 else "%d ATR" % cost]
		if cost > _available_points():
			_action_button.disabled = true
			_detail_status.text = "Not enough Attribute Points."
#endregion


#region Identity editing (creation only)
func _on_name_changed(text: String) -> void:
	if _character:
		_character.character_name = text.strip_edges()
		changed.emit()


func _on_title_changed(text: String) -> void:
	if _character:
		_character.title = text.strip_edges()
		changed.emit()


func _on_portrait_input(event: InputEvent) -> void:
	if _character == null or _portrait_paths.is_empty():
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var step := 0
	match event.button_index:
		MOUSE_BUTTON_LEFT: step = 1
		MOUSE_BUTTON_RIGHT: step = -1
	if step == 0:
		return
	var count := _portrait_paths.size()
	var index := (_portrait_paths.find(_character.portrait) + step + count) % count
	_character.portrait = _portrait_paths[index]
	_portrait.texture = load(_character.portrait)
	changed.emit()


static func list_portraits() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(PORTRAIT_DIR)
	if dir == null:
		push_warning("Portrait folder not found: %s" % PORTRAIT_DIR)
		return paths
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir():
			var base := file
			if base.ends_with(".import") or base.ends_with(".remap"):
				base = base.get_basename()
			if base.get_extension().to_lower() in PORTRAIT_EXTENSIONS:
				var path := PORTRAIT_DIR.path_join(base)
				if not paths.has(path):
					paths.append(path)
		file = dir.get_next()
	dir.list_dir_end()
	paths.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return paths
#endregion
