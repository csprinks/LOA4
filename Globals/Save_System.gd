# Save_System.gd
extends Node

## Reads/writes party + per-character JSON under user://saves/slot_<n>/.

const SAVE_DIR = "user://saves/"
const CHARACTER_FILE_PREFIX = "character_"
const PARTY_FILE = "party_data.json"
const WORLD_FILE = "world_state.json"

func _ready():
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

# Save a character to a specific slot.
func save_character(character: Character, slot: int, index: int) -> void:
	var slot_dir = SAVE_DIR + "slot_%d/" % slot
	DirAccess.make_dir_recursive_absolute(slot_dir)

	var file_path = slot_dir + CHARACTER_FILE_PREFIX + "%d.json" % index
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(character.to_json())
	else:
		push_error("Failed to save character: " + str(FileAccess.get_open_error()))

# Load a character from a slot.
func load_character(slot: int, index: int) -> Character:
	var char_path = SAVE_DIR + "slot_%d/" % slot + CHARACTER_FILE_PREFIX + "%d.json" % index
	if not FileAccess.file_exists(char_path):
		return null

	var file = FileAccess.open(char_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var character = Character.new()
		character.from_json(json_string)
		return character
	return null

func save_party(party_data: Dictionary, slot: int) -> void:
	var slot_dir = SAVE_DIR + "slot_%d/" % slot
	DirAccess.make_dir_recursive_absolute(slot_dir)

	var file_path = slot_dir + PARTY_FILE
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(party_data))
	else:
		push_error("Failed to save party: " + str(FileAccess.get_open_error()))


func load_party(slot: int) -> Dictionary:
	var party_path = SAVE_DIR + "slot_%d/" % slot + PARTY_FILE
	if not FileAccess.file_exists(party_path):
		return {}

	var file = FileAccess.open(party_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var save_data = JSON.parse_string(json_string)
		return save_data
	return {}

# World state (interactive objects + player location) for a slot. Written as a
# single blob alongside the party files, so a saved slot is a coherent snapshot.
func save_world(world_data: Dictionary, slot: int) -> void:
	var slot_dir = SAVE_DIR + "slot_%d/" % slot
	DirAccess.make_dir_recursive_absolute(slot_dir)

	var file_path = slot_dir + WORLD_FILE
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(world_data))
	else:
		push_error("Failed to save world state: " + str(FileAccess.get_open_error()))


func load_world(slot: int) -> Dictionary:
	var world_path = SAVE_DIR + "slot_%d/" % slot + WORLD_FILE
	if not FileAccess.file_exists(world_path):
		return {}

	var file = FileAccess.open(world_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var save_data = JSON.parse_string(json_string)
		if save_data is Dictionary:
			return save_data
	return {}


func party_save_exists(slot: int) -> bool:
	var party_path = SAVE_DIR + "slot_%d/" % slot + PARTY_FILE
	return FileAccess.file_exists(party_path)

# True if any slot in [0, count) has a saved party. Used to enable/disable the
# main menu's Load Game entry.
func any_save_exists(count: int) -> bool:
	for slot in range(count):
		if party_save_exists(slot):
			return true
	return false

# A light, read-only summary of a slot for the Load Game screen. Does NOT touch
# PartyManager or the active game — it just peeks at the files on disk.
# Returns { exists, names: [String], crowns: int }.
func get_slot_summary(slot: int) -> Dictionary:
	if not party_save_exists(slot):
		return {"exists": false, "names": [], "crowns": 0}

	var party = load_party(slot)
	var names: Array = []
	for char_index in party.get("characters", []):
		var character = load_character(slot, char_index)
		if character:
			names.append(character.character_name)

	return {
		"exists": true,
		"names": names,
		"crowns": int(party.get("crowns", 0)),
	}
