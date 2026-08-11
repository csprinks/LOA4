extends Node2D

## Coordinates the Character Creation screen: gathers each hero panel's choices
## into the party on "Start Game" and returns to the Main Menu otherwise.
##
## LOA4: "Start Game" drops straight into the walkable test room (no Library scene
## yet); "Return to Main Menu" goes back to the Main Menu scene.

const NEXT_SCENE := "res://Scenes/Test_Environment/Test_Environment.tscn"
const MENU_SCENE := "res://Scenes/Main_Menu/main_menu.tscn"

# Starter hand gear so new heroes have something in their equip slots. Temporary
# until the backpack UI lets players pick their own gear.
const STARTING_PRIMARY := "res://Inventory/Resources/Weapons/sword_1h.tres"
const STARTING_SECONDARY := "res://Inventory/Resources/Weapons/shield.tres"


func _ready() -> void:
	var start_button := get_node_or_null("%StartButton") as Button
	if start_button:
		start_button.pressed.connect(_on_start_game_pressed)

	var menu_button := get_node_or_null("%MainMenuButton") as Button
	if menu_button:
		menu_button.pressed.connect(_on_main_menu_pressed)


# The hero panels run character_creation.gd; find them wherever they sit in the
# tree (they live in an HBoxContainer under the UI layer), in tree order.
func _character_panels() -> Array:
	var panels := []
	_collect_panels(self, panels)
	return panels

func _collect_panels(node: Node, panels: Array) -> void:
	for child in node.get_children():
		if child.has_method("get_stat_data"):
			panels.append(child)
		else:
			_collect_panels(child, panels)


func _on_start_game_pressed() -> void:
	_build_party()
	# Hand off to LevelManager, which spawns the persistent player (HUD embedded)
	# into the first level. Then drop this creation screen; LevelManager runs its
	# fade + load as an autoload coroutine independent of this node.
	LevelManager.load_level(NEXT_SCENE)
	queue_free()


func _on_main_menu_pressed() -> void:
	_go_to_scene(MENU_SCENE)


func _build_party() -> void:
	var party_manager := get_node_or_null("/root/PartyManager")
	if party_manager == null:
		push_error("PartyManager autoload not found; cannot start game.")
		return

	party_manager.reset()

	# Fresh world for a brand-new game, so a new party never inherits a prior
	# session's open doors / looted chests.
	var world_state := get_node_or_null("/root/WorldState")
	if world_state:
		world_state.reset()

	# New games start with an empty shared backpack (loot comes from chests). This
	# also clears any backpack left over from a game loaded earlier this session.
	var inventory_manager := get_node_or_null("/root/InventoryManager")
	if inventory_manager and inventory_manager.has_method("reset_inventory"):
		inventory_manager.reset_inventory()

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
		# Deed Points the player left unspent at creation carry into the game as
		# the character's available pool for later stat growth.
		if panel.has_method("deeds_remaining"):
			character.available_deed_points = panel.deeds_remaining()
		_equip_starting_gear(character)

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


# Give a new hero starter hand gear (serialized into its equipment dict) so the
# card's equip slots show something. Temporary demo gear until the backpack UI.
func _equip_starting_gear(character) -> void:
	var events := get_node_or_null("/root/InventoryEvents")
	character.set_equipment_slot("primary", _weapon_dict(STARTING_PRIMARY, events))
	character.set_equipment_slot("secondary", _weapon_dict(STARTING_SECONDARY, events))

func _weapon_dict(path: String, events: Node) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var weapon := InventoryWeapon.new()
	weapon._resourceData = load(path)
	weapon.itemName = weapon._resourceData.itemName
	if events:
		weapon.SetInventoryEvents(events)
	return EquipmentSerializer.item_to_dict(weapon)


func _go_to_scene(path: String) -> void:
	var fade_manager := get_node_or_null("/root/FadeManager")
	if fade_manager:
		fade_manager.transition_to_scene(path)
	else:
		get_tree().change_scene_to_file(path)
