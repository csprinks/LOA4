extends CanvasLayer

## In-game system menu (Save / Load / Options / Quit), opened from the inventory
## screen's Menu button via InventoryEvents.ShowSystemMenu. It is a modal overlay
## that PAUSES the game and keeps you IN the session — it never returns to the
## title/Main Menu scene.
##
## Registered as the SystemMenu autoload so it's available in every level. Its root
## runs with PROCESS_MODE_ALWAYS so its buttons work while the tree is paused.
##
##   Save    → save the current party to the slot this game occupies (quick save).
##   Load    → pick a slot to load (reloads the world; confirms first).
##   Options → placeholder.
##   Quit    → quit to desktop (confirms first).

const WORLD_FALLBACK := "res://Scenes/Test_Environment/Test_Environment.tscn"

@onready var _root: Control = %Root
@onready var _main_panel: Control = %MainPanel
@onready var _slot_picker: Control = %SlotPicker
@onready var _slot_title: Label = %SlotTitle
@onready var _slots: VBoxContainer = %SlotsContainer
@onready var _confirm: Control = %Confirm
@onready var _confirm_text: Label = %ConfirmText
@onready var _confirm_yes: Button = %ConfirmYes
@onready var _confirm_cancel: Button = %ConfirmCancel
@onready var _flash: Label = %Flash

var _confirm_action: Callable = Callable()


func _ready() -> void:
	_root.visible = false
	_confirm.visible = false
	_flash.modulate.a = 0.0

	%SaveButton.pressed.connect(_on_save_pressed)
	%LoadButton.pressed.connect(_on_load_pressed)
	%OptionsButton.pressed.connect(_on_options_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%ResumeButton.pressed.connect(close)
	%SlotBack.pressed.connect(_show_main)
	_confirm_yes.pressed.connect(_on_confirm_yes)
	_confirm_cancel.pressed.connect(_hide_confirm)

	var events := get_node_or_null("/root/InventoryEvents")
	if events and events.has_signal("ShowSystemMenu"):
		events.ShowSystemMenu.connect(open)


func open() -> void:
	if _root.visible:
		return
	_show_main()
	_confirm.visible = false
	_root.visible = true
	get_tree().paused = true
	%SaveButton.grab_focus()


func close() -> void:
	_root.visible = false
	get_tree().paused = false


# Esc backs out one layer at a time (confirm → picker → main → closed).
func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _confirm.visible:
			_hide_confirm()
		elif _slot_picker.visible:
			_show_main()
		else:
			close()
		get_viewport().set_input_as_handled()


func _show_main() -> void:
	_main_panel.visible = true
	_slot_picker.visible = false


#region Save
func _on_save_pressed() -> void:
	if PartyManager.party.is_empty():
		_toast("Nothing to save yet")
		return
	PartyManager.save_party()  # writes to GameState.current_save_slot
	_toast("Saved to Slot %d" % (GameState.current_save_slot + 1))
#endregion


#region Load
func _on_load_pressed() -> void:
	if not SaveSystem.any_save_exists(GameState.SLOT_COUNT):
		_toast("No saved games found")
		return
	_slot_title.text = "Load Game"
	_build_load_slots()
	_main_panel.visible = false
	_slot_picker.visible = true


func _build_load_slots() -> void:
	for child in _slots.get_children():
		child.queue_free()

	var first_enabled: Button = null
	for slot in range(GameState.SLOT_COUNT):
		var summary: Dictionary = SaveSystem.get_slot_summary(slot)
		var enabled: bool = summary.get("exists", false)
		var card := SlotCard.build(slot, summary, enabled)
		if enabled:
			card.pressed.connect(_on_load_slot_chosen.bind(slot))
			if first_enabled == null:
				first_enabled = card
		_slots.add_child(card)

	if first_enabled:
		first_enabled.grab_focus()
	else:
		(%SlotBack as Button).grab_focus()


func _on_load_slot_chosen(slot: int) -> void:
	_ask_confirm(
		"Load Slot %d?\nAny unsaved progress will be lost." % (slot + 1),
		_do_load.bind(slot))


func _do_load(slot: int) -> void:
	GameState.current_save_slot = slot
	GameState.new_game_requested = false
	PartyManager.reset()
	PartyManager.initialize_party()  # loads the slot's party from disk

	# Load the slot's world state; prepare_load arms the player-spawn override and
	# returns the saved level (or "" for an older save with no world blob).
	var level: String = WorldState.prepare_load(slot)
	if level == "":
		level = WORLD_FALLBACK
	_hide_confirm()
	close()  # unpause so LevelManager's fade/awaits can run
	LevelManager.load_level(level)
#endregion


func _on_options_pressed() -> void:
	_toast("Options — coming soon")


func _on_quit_pressed() -> void:
	_ask_confirm(
		"Quit to desktop?\nAny unsaved progress will be lost.",
		func() -> void: get_tree().quit())


#region Confirmation dialog
func _ask_confirm(text: String, action: Callable) -> void:
	_confirm_text.text = text
	_confirm_action = action
	_confirm.visible = true
	_confirm_yes.grab_focus()


func _on_confirm_yes() -> void:
	var action := _confirm_action
	_confirm_action = Callable()
	_confirm.visible = false
	if action.is_valid():
		action.call()


func _hide_confirm() -> void:
	_confirm.visible = false
	_confirm_action = Callable()
#endregion


# A brief status message near the bottom of the overlay (save result, placeholders).
func _toast(message: String) -> void:
	_flash.text = message
	_flash.modulate.a = 1.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # animate while the game is paused
	tween.tween_interval(1.2)
	tween.tween_property(_flash, "modulate:a", 0.0, 0.6)
