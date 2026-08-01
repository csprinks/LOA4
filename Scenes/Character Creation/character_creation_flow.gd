extends Node2D

## Coordinates the Character Creation screen: gathers each hero panel's choices
## into the party on "Start Game" and returns to the menu otherwise.
##
## LOA4 phase 2: there is no Main Menu or Library scene yet, so "Start Game"
## drops straight into the walkable test room and "Return to Main Menu" reloads
## this screen. Repoint these constants once those scenes are ported.

const NEXT_SCENE := "res://Scenes/Test_Environment/Test_Environment.tscn"
const MENU_SCENE := "res://Scenes/Character Creation/character_creation.tscn"


func _ready() -> void:
	var start_button := get_node_or_null("CanvasLayer/Start Game") as Button
	if start_button:
		start_button.pressed.connect(_on_start_game_pressed)

	var menu_button := get_node_or_null("CanvasLayer/Main Menu") as Button
	if menu_button:
		menu_button.pressed.connect(_on_main_menu_pressed)


# Each hero panel is a CanvasLayer running character_creation.gd, in tree order.
func _character_panels() -> Array:
	var panels := []
	for child in get_children():
		if child.has_method("get_stat_data"):
			panels.append(child)
	return panels


func _on_start_game_pressed() -> void:
	_build_party()
	_go_to_scene(NEXT_SCENE)


func _on_main_menu_pressed() -> void:
	_go_to_scene(MENU_SCENE)


func _build_party() -> void:
	var party_manager := get_node_or_null("/root/PartyManager")
	if party_manager == null:
		push_error("PartyManager autoload not found; cannot start game.")
		return

	party_manager.reset()

	var new_party := []
	var index := 0
	for panel in _character_panels():
		var character := Character.new()

		var hero_name: String = panel.get_hero_name()
		if hero_name == "":
			hero_name = "Hero %d" % (index + 1)
		character.character_name = hero_name

		var portrait: String = panel.get_portrait_path()
		if portrait != "":
			character.portrait = portrait

		character.primary_class = panel.get_primary_class()
		character.secondary_class = panel.get_secondary_class()
		character.apply_stat_data(panel.get_stat_data())

		new_party.append(character)
		index += 1

	party_manager.party = new_party
	party_manager.current_character_index = 0
	# Mark initialized so downstream systems keep this party instead of replacing
	# it with a default one. Clear the new-game flag so initialize_party() (if it
	# runs) won't rebuild a fresh party either.
	party_manager.is_initialized = true
	GameState.new_game_requested = false
	party_manager.emit_signal("party_updated")


func _go_to_scene(path: String) -> void:
	var fade_manager := get_node_or_null("/root/FadeManager")
	if fade_manager:
		fade_manager.transition_to_scene(path)
	else:
		get_tree().change_scene_to_file(path)
