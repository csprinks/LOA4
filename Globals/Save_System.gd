# Save_System.gd
extends Node

## Reads/writes party + per-character JSON under user://saves/slot_<n>/.

const SAVE_DIR = "user://saves/"
const CHARACTER_FILE_PREFIX = "character_"
const PARTY_FILE = "party_data.json"

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

func party_save_exists(slot: int) -> bool:
	var party_path = SAVE_DIR + "slot_%d/" % slot + PARTY_FILE
	return FileAccess.file_exists(party_path)
