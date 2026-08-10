extends Node2D

## New Game slot picker — choose which slot a fresh game occupies, then head to
## Character Creation. Every slot is selectable; picking one that already holds a
## save asks for confirmation first.
##
## Per the save-coherence rule, choosing a slot does NOT wipe its file here: the
## fresh party lives in memory and only replaces the slot's save when the player
## actually saves in-game. The confirmation says as much.
##
## Visual style matches the Load Game screen (shared SlotCard builder).

const MAIN_MENU := "res://Scenes/Main_Menu/main_menu.tscn"
const CHARACTER_CREATION := "res://Scenes/Character Creation/character_creation.tscn"

@onready var _slots: VBoxContainer = %SlotsContainer
@onready var _back_button: Button = %BackButton
@onready var _confirm_overlay: Control = %ConfirmOverlay
@onready var _confirm_text: Label = %ConfirmText
@onready var _confirm_yes: Button = %ConfirmYes
@onready var _confirm_cancel: Button = %ConfirmCancel

var _pending_slot: int = -1


func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	_confirm_yes.pressed.connect(_on_confirm_yes)
	_confirm_cancel.pressed.connect(_on_confirm_cancel)
	_confirm_overlay.visible = false
	_build_slots()


func _build_slots() -> void:
	var first: Button = null
	for slot in range(GameState.SLOT_COUNT):
		var summary: Dictionary = SaveSystem.get_slot_summary(slot)
		# Every slot is a valid target for a new game.
		var card := SlotCard.build(slot, summary, true)
		card.pressed.connect(_on_slot_chosen.bind(slot, summary))
		_slots.add_child(card)
		if first == null:
			first = card

	if first:
		first.grab_focus()
	else:
		_back_button.grab_focus()


func _on_slot_chosen(slot: int, summary: Dictionary) -> void:
	if summary.get("exists", false):
		# Occupied slot — confirm before committing.
		_pending_slot = slot
		_confirm_text.text = "Slot %d already has a saved party.\nStarting a new game here will replace it when you save.\n\nContinue?" % (slot + 1)
		_confirm_overlay.visible = true
		_confirm_yes.grab_focus()
	else:
		_start_new_game(slot)


func _on_confirm_yes() -> void:
	_confirm_overlay.visible = false
	if _pending_slot >= 0:
		_start_new_game(_pending_slot)


func _on_confirm_cancel() -> void:
	_confirm_overlay.visible = false
	_pending_slot = -1
	# Return focus to the slot list.
	if _slots.get_child_count() > 0:
		(_slots.get_child(0) as Control).grab_focus()


func _start_new_game(slot: int) -> void:
	GameState.current_save_slot = slot
	GameState.new_game_requested = true
	PartyManager.reset()
	WorldState.reset()  # fresh world: don't inherit a prior session's interactive state
	FadeManager.transition_to_scene(CHARACTER_CREATION)


func _on_back_pressed() -> void:
	FadeManager.transition_to_scene(MAIN_MENU)
