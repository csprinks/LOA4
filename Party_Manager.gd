extends Node

## Holds the active party (up to 4 Characters), the selected hero index, and
## coordinates persistence through SaveSystem. Save coherence rules (carried over
## from LOA2): "Start New Game" builds a fresh party in memory without touching
## the slot's existing save; hero switching never writes to disk; all disk saves
## go through save_party() as a full snapshot.

var party: Array = []
var current_character_index: int = 0
var is_initialized: bool = false
var previous_character_index: int = -1
const DEBUG := true
const SAVE_CHARACTER_COUNT = 4

signal party_updated

func _ready() -> void:
	if DEBUG: print("PartyManager: Ready")
	previous_character_index = 0

func initialize_party() -> void:
	if is_initialized:
		if DEBUG: print("Party already initialized")
		return

	# "Start New Game" forces a fresh party even if a save exists in this slot.
	# The existing save file is left untouched until the player actually saves.
	if GameState.new_game_requested:
		GameState.new_game_requested = false
		if DEBUG: print("New game requested - creating new party")
		create_new_party(false)
		is_initialized = true
		emit_signal("party_updated")
		return

	var save_data = SaveSystem.load_party(GameState.current_save_slot)

	if save_data and save_data.has("characters") and not save_data["characters"].is_empty():
		if DEBUG: print("Loading party from save")
		load_from_save(save_data)
		is_initialized = true
	else:
		if DEBUG: print("No saved party found - creating new")
		create_new_party()
		is_initialized = true

	emit_signal("party_updated")

# persist: when false, the fresh party is only held in memory and the slot's
# existing save on disk is left untouched (used by "Start New Game" so a misclick
# can't overwrite an existing save until the player explicitly saves).
func create_new_party(persist: bool = true) -> void:
	print("Creating new party")
	party = []

	for i in range(SAVE_CHARACTER_COUNT):
		var char_name = "Hero " + str(i + 1)
		var character = Character.new()
		character.character_name = char_name
		character.portrait = "res://Portraits/Portrait_%d.png" % (i + 1)

		party.append(character)
		if persist:
			save_character(character)

	if DEBUG:
		print("PartyManager: Created new default party")

	emit_signal("party_updated")

func save_party():
	if party.size() == 0:
		if DEBUG: push_error("Cannot save empty party!")
		return

	var party_data = {
		"characters": [],
		"current_index": current_character_index,
		"crowns": Crowns.get_crowns()
	}

	for i in range(party.size()):
		save_character(party[i])
		party_data["characters"].append(i)

	SaveSystem.save_party(party_data, GameState.current_save_slot)

	if DEBUG: print("Saved party to slot ", GameState.current_save_slot)

func load_from_save(save_data: Dictionary):
	Crowns.crowns = save_data.get("crowns", 0)
	print("Loading party from save")
	party = []
	current_character_index = save_data.get("current_index", 0)

	for char_index in save_data.get("characters", []):
		var character = SaveSystem.load_character(GameState.current_save_slot, char_index)
		if character:
			party.append(character)

	emit_signal("party_updated")

func save_character(character: Character) -> void:
	if not character:
		if DEBUG: push_error("Attempted to save null character!")
		return

	if DEBUG:
		print("PartyManager: Saving character: ", character.character_name)

	var index = party.find(character)
	if index != -1:
		SaveSystem.save_character(character, GameState.current_save_slot, index)

func get_current_character() -> Character:
	if party.size() == 0:
		if DEBUG: push_error("Party is empty! Cannot get character.")
		return null

	if current_character_index >= 0 && current_character_index < party.size():
		return party[current_character_index]

	if DEBUG: push_error("Invalid character index: ", current_character_index)
	return null

func next_character() -> void:
	if party.size() == 0:
		if DEBUG: push_error("Cannot switch character - party is empty!")
		return

	# Switching the selected hero is pure navigation - it must not write to disk.
	# The in-memory party keeps every hero's state; persistence happens on
	# explicit save (menu) and coherent auto-saves (e.g. spending crowns).
	previous_character_index = current_character_index
	current_character_index = (current_character_index + 1) % party.size()
	emit_signal("party_updated")

func prev_character() -> void:
	if party.size() == 0:
		if DEBUG: push_error("Cannot switch character - party is empty!")
		return

	previous_character_index = current_character_index
	current_character_index = (current_character_index - 1) % party.size()
	if current_character_index < 0:
		current_character_index = party.size() - 1
	emit_signal("party_updated")

# Persist the game as a coherent snapshot (all character files + party_data
# together), so every on-disk save is internally consistent.
func save_current_character() -> void:
	if party.size() == 0:
		if DEBUG: push_error("Cannot save character - party is empty!")
		return

	save_party()
	emit_signal("party_updated")

func get_previous_character() -> Character:
	if party.size() == 0:
		return null

	if previous_character_index >= 0 and previous_character_index < party.size():
		return party[previous_character_index]
	return null

func get_character(index: int) -> Character:
	if party.size() == 0:
		return null

	if index >= 0 and index < party.size():
		return party[index]
	return null

func reset() -> void:
	party = []
	current_character_index = 0
	is_initialized = false
	previous_character_index = -1
	if DEBUG:
		print("PartyManager: Reset complete")

func spend_crowns(amount: int) -> bool:
	if Crowns.get_crowns() >= amount:
		Crowns.spend_crowns(amount)
		emit_signal("party_updated")
		save_party()
		return true
	return false
