extends Node2D

## Load Game screen — one card per save slot. A populated slot shows its party
## and crowns and loads into the world when clicked; an empty slot is greyed out.
## Slot count comes from GameState.SLOT_COUNT.
##
## Visual style matches the Main Menu: brown background + shared game_theme.

const MAIN_MENU := "res://Scenes/Main_Menu/main_menu.tscn"
const WORLD_SCENE := "res://Scenes/Test_Environment/Test_Environment.tscn"

@onready var _slots: VBoxContainer = %SlotsContainer
@onready var _back_button: Button = %BackButton
@onready var _confirm_overlay: Control = %ConfirmOverlay
@onready var _confirm_text: Label = %ConfirmText
@onready var _confirm_yes: Button = %ConfirmYes
@onready var _confirm_cancel: Button = %ConfirmCancel

var _pending_delete_slot: int = -1


func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	_confirm_yes.pressed.connect(_on_confirm_delete)
	_confirm_cancel.pressed.connect(_on_cancel_delete)
	_confirm_overlay.visible = false
	_build_slots()


func _build_slots() -> void:
	# Rebuilt after a delete, so clear any existing cards first.
	for child in _slots.get_children():
		child.queue_free()

	var first_enabled: Button = null
	for slot in range(GameState.SLOT_COUNT):
		var summary: Dictionary = SaveSystem.get_slot_summary(slot)
		var enabled: bool = summary.get("exists", false)  # only populated slots load
		var card := SlotCard.build(slot, summary, enabled, true)  # show delete on populated slots
		if enabled:
			card.pressed.connect(_on_slot_pressed.bind(slot))
			var delete_btn := card.find_child("DeleteButton", true, false)
			if delete_btn:
				delete_btn.pressed.connect(_on_delete_pressed.bind(slot))
		_slots.add_child(card)
		if enabled and first_enabled == null:
			first_enabled = card

	# Land keyboard/controller focus on the first loadable slot, else on Back.
	if first_enabled:
		first_enabled.grab_focus()
	else:
		_back_button.grab_focus()


# Ask before wiping a slot's save.
func _on_delete_pressed(slot: int) -> void:
	_pending_delete_slot = slot
	_confirm_text.text = "Delete Slot %d?\nThis cannot be undone." % (slot + 1)
	_confirm_overlay.visible = true
	_confirm_yes.grab_focus()


func _on_confirm_delete() -> void:
	_confirm_overlay.visible = false
	if _pending_delete_slot >= 0:
		SaveSystem.delete_save(_pending_delete_slot)
		_pending_delete_slot = -1
		_build_slots()


func _on_cancel_delete() -> void:
	_confirm_overlay.visible = false
	_pending_delete_slot = -1
	if _slots.get_child_count() > 0:
		(_slots.get_child(0) as Control).grab_focus()


# Load the chosen slot's party and drop into the world.
func _on_slot_pressed(slot: int) -> void:
	GameState.current_save_slot = slot
	GameState.new_game_requested = false
	PartyManager.reset()
	PartyManager.initialize_party()  # loads the slot's party from disk

	# Load the slot's world state; prepare_load arms the player-spawn override and
	# returns the saved level (or "" for an older save with no world blob).
	var target: String = WorldState.prepare_load(slot)
	if target == "":
		target = WORLD_SCENE

	await FadeManager.fade_out()
	queue_free()
	LevelManager.load_level(target)


func _on_back_pressed() -> void:
	FadeManager.transition_to_scene(MAIN_MENU)
