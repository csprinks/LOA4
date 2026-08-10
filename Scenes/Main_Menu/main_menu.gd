extends Node2D

## Main Menu — the game's entry scene.
##
##   New Game  → open the slot picker, then build a fresh party in Character Creation.
##   Load Game → open the slot picker (disabled when no slot has a save).
##   Options   → placeholder (flashes a "coming soon" note for now).
##   Tutorial  → placeholder (same).
##   Quit      → exit to the desktop.
##
## Visual style matches Character Creation: solid brown background + the shared
## game_theme, driven through FadeManager for transitions.

const NEW_GAME := "res://Scenes/Main_Menu/new_game.tscn"
const LOAD_GAME := "res://Scenes/Main_Menu/load_game.tscn"

@onready var _load_button: Button = %LoadGameButton
@onready var _flash_label: Label = %FlashLabel


func _ready() -> void:
	%NewGameButton.pressed.connect(_on_new_game_pressed)
	_load_button.pressed.connect(_on_load_game_pressed)
	%OptionsButton.pressed.connect(_on_placeholder_pressed.bind("Options"))
	%TutorialButton.pressed.connect(_on_placeholder_pressed.bind("Tutorial"))
	%QuitButton.pressed.connect(_on_quit_pressed)

	# Nothing to load until a party has been saved to at least one slot.
	_load_button.disabled = not SaveSystem.any_save_exists(GameState.SLOT_COUNT)

	_flash_label.modulate.a = 0.0
	%NewGameButton.grab_focus()


# Open the slot picker; it sets the target slot and flags before Character Creation.
func _on_new_game_pressed() -> void:
	_go_to_scene(NEW_GAME)


# Open the slot picker (the button is disabled when no slot has a save).
func _on_load_game_pressed() -> void:
	_go_to_scene(LOAD_GAME)


func _on_placeholder_pressed(feature_name: String) -> void:
	_flash("%s — coming soon" % feature_name)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _go_to_scene(path: String) -> void:
	if FadeManager:
		FadeManager.transition_to_scene(path)
	else:
		get_tree().change_scene_to_file(path)


# Briefly show a status message beneath the buttons, then fade it out.
func _flash(message: String) -> void:
	if not _flash_label:
		return
	_flash_label.text = message
	_flash_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(_flash_label, "modulate:a", 0.0, 0.6)
