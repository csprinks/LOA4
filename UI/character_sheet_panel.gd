class_name CharacterSheetPanel
extends CanvasLayer

## The in-game character sheet: a modal wrapper around CharacterSheet. Opened by
## clicking a hero's portrait (or ATR readout) on the HUD, or with C. Skill
## purchases are a draft until Confirm; Close (or Esc / C) discards the draft.
## Tab / the arrow buttons step through the party once nothing is pending.
##
## Built in code and pauses the game while open.

const THEME := preload("res://UI/game_theme.tres")
const GROUP := "character_sheet_panel"
const TOGGLE_KEY := KEY_C

var _party: Array = []
var _index := 0
var _applied := false
var _was_paused := false

var _sheet: CharacterSheet
var _title: Label
var _prev: Button
var _next: Button
var _confirm: Button


# Open the sheet for `character`, parented under `host`'s scene tree root. Returns
# null if a sheet is already open.
static func open_for(character: Character, host: Node) -> CharacterSheetPanel:
	if character == null or host.get_tree().get_first_node_in_group(GROUP) != null:
		return null
	var panel := CharacterSheetPanel.new()
	var party_manager := host.get_node_or_null("/root/PartyManager")
	panel._party = party_manager.party.duplicate() if party_manager else []
	if not panel._party.has(character):
		panel._party = [character]
	panel._index = panel._party.find(character)
	host.get_tree().root.add_child(panel)
	return panel


func _ready() -> void:
	layer = 55   # above the HUD/inventory, below the system menu (60)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	_build()
	_show_hero(_index)
	_was_paused = get_tree().paused
	get_tree().paused = true


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
		margin.add_theme_constant_override("margin_" + side, 22)
	frame.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 18)
	col.add_child(header)

	_prev = Button.new()
	_prev.text = "<"
	_prev.custom_minimum_size = Vector2(44, 0)
	_prev.pressed.connect(_step_hero.bind(-1))
	header.add_child(_prev)

	_title = Label.new()
	_title.custom_minimum_size = Vector2(420, 0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", UIStyle.GOLD)
	header.add_child(_title)

	_next = Button.new()
	_next.text = ">"
	_next.custom_minimum_size = Vector2(44, 0)
	_next.pressed.connect(_step_hero.bind(1))
	header.add_child(_next)

	col.add_child(HSeparator.new())

	_sheet = CharacterSheet.new()
	_sheet.changed.connect(_refresh_buttons)
	col.add_child(_sheet)

	col.add_child(HSeparator.new())

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)

	_confirm = Button.new()
	_confirm.text = "Confirm"
	_confirm.add_theme_font_size_override("font_size", 22)
	_confirm.custom_minimum_size = Vector2(170, 0)
	_confirm.pressed.connect(_on_confirm)
	buttons.add_child(_confirm)

	var close := Button.new()
	close.text = "Close"
	close.add_theme_font_size_override("font_size", 22)
	close.custom_minimum_size = Vector2(170, 0)
	close.pressed.connect(_close)
	buttons.add_child(close)


func _show_hero(index: int) -> void:
	_index = index
	_sheet.bind(_party[_index])
	_title.text = "Character Sheet  (%d / %d)" % [_index + 1, _party.size()]
	_refresh_buttons()


# Switching heroes would silently drop a draft, so it waits until the draft is
# confirmed or undone.
func _step_hero(step: int) -> void:
	if _party.size() < 2 or _sheet.has_pending():
		return
	_show_hero((_index + step + _party.size()) % _party.size())


func _refresh_buttons() -> void:
	var pending := _sheet.has_pending()
	_confirm.disabled = not pending
	_prev.disabled = pending or _party.size() < 2
	_next.disabled = pending or _party.size() < 2


func _on_confirm() -> void:
	_sheet.commit()
	_applied = true
	_refresh_buttons()


func _close() -> void:
	get_tree().paused = _was_paused
	# Stats and spendable points changed: let the HUD cards re-read their heroes.
	var party_manager := get_node_or_null("/root/PartyManager")
	if _applied and party_manager:
		party_manager.party_updated.emit()
	queue_free()


# _input rather than _unhandled_input: Tab would otherwise be eaten by GUI focus
# navigation before it got here.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY):
		get_viewport().set_input_as_handled()
		_close()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		_step_hero(-1 if event.shift_pressed else 1)
