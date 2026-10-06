class_name LevelUpPanel
extends CanvasLayer

## Modal panel for spending a hero's banked Attribute Points (earned on level-up,
## plus any left over from creation). Opened from the ATR readout on the hero's
## HUD card. Points are allocated as a draft -- freely adjustable with +/- -- and
## only written to the Character on Confirm. Each point raises a stat by the Gain
## fixed by the hero's classes at creation; Might also adds flat HP.
##
## Built in code (like the creation panel) and pauses the game while open.

signal closed(applied: bool)

const THEME := preload("res://UI/game_theme.tres")
const FONT := 20

var _character: Character
var _draft: Dictionary = {}          # stat name -> points allocated in this session
var _was_paused := false

var _points_label: Label
var _hp_label: Label
var _confirm: Button
var _new_labels: Dictionary = {}     # stat name -> Label (total after the draft)
var _draft_labels: Dictionary = {}   # stat name -> Label (points drafted)
var _minus_buttons: Dictionary = {}
var _plus_buttons: Dictionary = {}


# Open the panel for `character`, parented under `host`'s scene tree root.
static func open_for(character: Character, host: Node) -> LevelUpPanel:
	var panel := LevelUpPanel.new()
	panel._character = character
	host.get_tree().root.add_child(panel)
	return panel


func _ready() -> void:
	layer = 55   # above the HUD/inventory, below the system menu (60)
	process_mode = Node.PROCESS_MODE_ALWAYS
	for stat in Character.STAT_NAMES:
		_draft[stat] = 0
	_build()
	_refresh()
	_was_paused = get_tree().paused
	get_tree().paused = true


func _label(text: String, size: int = FONT, color: Color = UIStyle.CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build() -> void:
	var root := Control.new()
	root.theme = THEME
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var frame := PanelContainer.new()
	center.add_child(frame)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	frame.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := _label("%s  -  Level %d" % [_character.character_name, _character.level_system.current_level], 32, UIStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_points_label = _label("", 22, UIStyle.GOLD_BRIGHT)
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_points_label)

	col.add_child(HSeparator.new())

	# Stat | Now | - | drafted | + | Gain | New
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)

	for header in ["Stat", "Now", "", "ATR", "", "Gain", "New"]:
		grid.add_child(_label(header, 15, UIStyle.MUTED))

	for stat in Character.STAT_NAMES:
		var s: Stat = _character.get_stat(stat)
		grid.add_child(_label(stat))
		grid.add_child(_centered(_label(str(s.total))))

		var minus := Button.new()
		minus.text = "-"
		minus.custom_minimum_size = Vector2(36, 0)
		minus.pressed.connect(_adjust.bind(stat, -1))
		_minus_buttons[stat] = minus
		grid.add_child(minus)

		var drafted := _centered(_label("0"))
		drafted.custom_minimum_size = Vector2(28, 0)
		_draft_labels[stat] = drafted
		grid.add_child(drafted)

		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(36, 0)
		plus.pressed.connect(_adjust.bind(stat, 1))
		_plus_buttons[stat] = plus
		grid.add_child(plus)

		grid.add_child(_centered(_label("+%d" % s.gain_per_point, FONT, UIStyle.MUTED)))

		var new_total := _centered(_label(str(s.total)))
		_new_labels[stat] = new_total
		grid.add_child(new_total)

	col.add_child(HSeparator.new())

	_hp_label = _label("", 18)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hp_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)

	_confirm = Button.new()
	_confirm.text = "Confirm"
	_confirm.custom_minimum_size = Vector2(150, 0)
	_confirm.pressed.connect(_on_confirm)
	buttons.add_child(_confirm)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(150, 0)
	cancel.pressed.connect(_close.bind(false))
	buttons.add_child(cancel)

	(_plus_buttons[Character.STAT_NAMES[0]] as Button).grab_focus.call_deferred()


func _centered(label: Label) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _drafted_total() -> int:
	var total := 0
	for stat in _draft:
		total += int(_draft[stat])
	return total


func _adjust(stat: String, delta: int) -> void:
	var remaining := _character.available_attribute_points - _drafted_total()
	if (delta > 0 and remaining <= 0) or (delta < 0 and int(_draft[stat]) <= 0):
		return
	_draft[stat] += delta
	_refresh()


func _refresh() -> void:
	var remaining := _character.available_attribute_points - _drafted_total()
	_points_label.text = "Attribute Points: %d" % remaining

	for stat in Character.STAT_NAMES:
		var s: Stat = _character.get_stat(stat)
		var drafted := int(_draft[stat])
		_draft_labels[stat].text = str(drafted)
		_new_labels[stat].text = str(s.total + drafted * s.gain_per_point)
		_new_labels[stat].add_theme_color_override("font_color",
			UIStyle.GOLD_BRIGHT if drafted > 0 else UIStyle.CREAM)
		_minus_buttons[stat].disabled = drafted <= 0
		_plus_buttons[stat].disabled = remaining <= 0

	# Mirrors Character.compute_max_hp: flat HP per point spent in Might.
	var hp_now: int = _character.hit_points.max_value
	var hp_gain: int = Character.HP_PER_MIGHT_POINT * int(_draft["Might"])
	if hp_gain > 0:
		_hp_label.text = "Max HP: %d  ->  %d" % [hp_now, hp_now + hp_gain]
	else:
		_hp_label.text = "Max HP: %d  (+%d per point in Might)" % [hp_now, Character.HP_PER_MIGHT_POINT]

	_confirm.disabled = _drafted_total() == 0


func _on_confirm() -> void:
	_close(_character.spend_attribute_points(_draft))


func _close(applied: bool) -> void:
	get_tree().paused = _was_paused
	closed.emit(applied)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close(false)
