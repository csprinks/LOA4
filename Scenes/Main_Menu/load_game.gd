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


func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	_build_slots()


func _build_slots() -> void:
	var first_enabled: Button = null
	for slot in range(GameState.SLOT_COUNT):
		var summary: Dictionary = SaveSystem.get_slot_summary(slot)
		var enabled: bool = summary.get("exists", false)  # only populated slots load
		var card := SlotCard.build(slot, summary, enabled)
		if enabled:
			card.pressed.connect(_on_slot_pressed.bind(slot))
		_slots.add_child(card)
		if enabled and first_enabled == null:
			first_enabled = card

	# Land keyboard/controller focus on the first loadable slot, else on Back.
	if first_enabled:
		first_enabled.grab_focus()
	else:
		_back_button.grab_focus()


# Load the chosen slot's party and drop into the world.
func _on_slot_pressed(slot: int) -> void:
	GameState.current_save_slot = slot
	GameState.new_game_requested = false
	PartyManager.reset()
	PartyManager.initialize_party()  # loads the slot's party from disk

	await FadeManager.fade_out()
	queue_free()
	LevelManager.load_level(WORLD_SCENE)


func _on_back_pressed() -> void:
	FadeManager.transition_to_scene(MAIN_MENU)
